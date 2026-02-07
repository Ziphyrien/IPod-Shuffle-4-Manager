#!/usr/bin/env python3

# Builtin libraries
import sys
import struct
import urllib.request, urllib.parse, urllib.error
import os
import hashlib
import subprocess
import collections
import errno
import argparse
import shutil
import re
import tempfile
import signal
import threading
import math
from concurrent.futures import ThreadPoolExecutor, as_completed

# External libraries
import asyncio
import av

try:
    import edge_tts
except ImportError:
    edge_tts = None

try:
    import mutagen
except ImportError:
    mutagen = None

audio_ext = (".mp3", ".m4a", ".m4b", ".m4p", ".aa", ".wav", ".flac")
list_ext = (".pls", ".m3u")
music_ext = tuple(ext for ext in audio_ext if ext != ".flac")

verboseprint = lambda *a, **k: None

# 用于并发打印的锁
_print_lock = threading.Lock()

def _safe_print(*args, **kwargs):
    """线程安全的打印函数"""
    with _print_lock:
        print(*args, **kwargs)

def is_subpath(path, parent):
    try:
        abs_path = os.path.normcase(os.path.abspath(path))
        abs_parent = os.path.normcase(os.path.abspath(parent))
        return os.path.commonpath([abs_path, abs_parent]) == abs_parent
    except ValueError:
        return False

def convert_flac_to_mp3(flac_path):
    """使用 pyav 将 FLAC 转换为 320kbps MP3，并删除源文件"""
    mp3_path = os.path.splitext(flac_path)[0] + '.mp3'
    
    # 如果 MP3 已存在，只需删除 FLAC 源文件（如果存在）
    if os.path.exists(mp3_path):
        if os.path.exists(flac_path):
            with _print_lock:
                verboseprint(f"MP3 已存在，删除源文件: {os.path.basename(flac_path)}")
            os.remove(flac_path)
        return mp3_path
    
    with _print_lock:
        verboseprint(f"转换 FLAC -> MP3: {os.path.basename(flac_path)}")
    
    input_container = None
    output_container = None

    try:
        input_container = av.open(flac_path)
        output_container = av.open(mp3_path, 'w')
        
        # 获取输入音频流
        input_stream = input_container.streams.audio[0]
        
        # MP3 采样率通常为 44100 或 48000
        target_rate = 44100
        if input_stream.rate >= 48000:
             target_rate = 48000
             
        # 创建 320kbps MP3 输出流
        output_stream = output_container.add_stream('mp3', rate=target_rate)
        output_stream.bit_rate = 320000 
        output_stream.layout = 'stereo'
        output_stream.format = 'fltp'

        # 创建重采样器
        resampler = av.AudioResampler(
            format=output_stream.format,
            layout=output_stream.layout,
            rate=output_stream.rate,
        )
        
        # 使用 demux 手动解封装，以便处理单个数据包的错误
        for packet in input_container.demux(input_stream):
            try:
                # 如果 packet.dts 为 None，可能是无效包，但在某些格式中是正常的
                # 解码数据包
                for frame in packet.decode():
                    frame.pts = None
                    for resampled_frame in resampler.resample(frame):
                        for out_packet in output_stream.encode(resampled_frame):
                            output_container.mux(out_packet)
            except av.error.InvalidDataError as e:
                with _print_lock:
                    verboseprint(f"跳过损坏的数据包: {e}")
                continue
        
        # 刷新重采样器
        for resampled_frame in resampler.resample(None):
             for packet in output_stream.encode(resampled_frame):
                output_container.mux(packet)

        # 刷新编码器
        for packet in output_stream.encode():
            output_container.mux(packet)
            
        # 必须先关闭容器，mutagen 才能写入
        input_container.close()
        input_container = None
        output_container.close()
        output_container = None
        # 尝试复制 ID3 标签
        if mutagen:
            try:
                # 读取源文件标签
                f_src = mutagen.File(flac_path, easy=True)
                if not f_src:
                    f_src = mutagen.File(flac_path) # Retry without easy=True
                
                # 读取目标文件标签 (如果不存在会自动创建)
                try:
                    f_dest = mutagen.File(mp3_path, easy=True)
                except:
                    # 如果读取失败，尝试手动添加 ID3 头
                    from mutagen.mp3 import EasyMP3
                    from mutagen.id3 import ID3NoHeaderError
                    try:
                        f_dest = EasyMP3(mp3_path)
                    except ID3NoHeaderError:
                        f_dest = EasyMP3(mp3_path)
                        f_dest.add_tags()
                
                if f_src is not None and f_dest is not None:
                    changed = False
                    for k in f_src:
                        try:
                            f_dest[k] = f_src[k]
                            changed = True
                        except Exception:
                            pass
                    
                    if changed:
                        f_dest.save()
                        with _print_lock:
                            verboseprint(f"已复制标签: {', '.join(f_src.keys())}")
                else:
                    verboseprint(f"标签对象无效: src={type(f_src)}, dest={type(f_dest)}")

            except Exception as e:
                _safe_print(f"警告: 复制标签失败: {e}")

        # 转换成功后删除源文件
        if os.path.exists(flac_path):
            with _print_lock:
                verboseprint(f"删除源文件: {flac_path}")
            try:
                os.remove(flac_path)
            except OSError as e:
                _safe_print(f"删除源文件失败: {e}")
            
    except Exception as e:
        _safe_print(f"转换失败: {e}")
        
        # 确保容器关闭
        if input_container:
            try: input_container.close()
            except: pass
        if output_container:
            try: output_container.close()
            except: pass
            
        # 转换失败时不删除源文件，可能需要清理部分生成的 MP3
        if os.path.exists(mp3_path):
            try:
                os.remove(mp3_path)
            except OSError as del_err:
                 _safe_print(f"警告: 无法删除不完整的 MP3 文件: {del_err}")
        return None
    
    return mp3_path


def make_dir_if_absent(path):
    try:
        os.makedirs(path)
    except OSError as exc:
        if exc.errno != errno.EEXIST:
            raise

def raises_unicode_error(str):
    try:
        str.encode('latin-1')
        return False
    except (UnicodeEncodeError, UnicodeDecodeError):
        return True

def hash_error_unicode(item):
    item_bytes = item.encode('utf-8')
    return "".join(["{0:02X}".format(ord(x)) for x in reversed(hashlib.md5(item_bytes).hexdigest()[:8])])

def validate_unicode(path):
    path_list = path.split('/')
    last_raise = False
    for i in range(len(path_list)):
        if raises_unicode_error(path_list[i]):
            path_list[i] = hash_error_unicode(path_list[i])
            last_raise = True
        else:
            last_raise = False
    extension = os.path.splitext(path)[1].lower()
    return "/".join(path_list) + (extension if last_raise and extension in audio_ext else '')

def exec_exists_in_path(command):
    with open(os.devnull, 'w') as FNULL:
        try:
            with open(os.devnull, 'r') as RFNULL:
                subprocess.call([command], stdout=FNULL, stderr=subprocess.STDOUT, stdin=RFNULL)
                return True
        except OSError as e:
            return False

def splitpath(path):
    return path.split(os.sep)

def get_relpath(path, basepath):
    commonprefix = os.sep.join(os.path.commonprefix(list(map(splitpath, [path, basepath]))))
    return os.path.relpath(path, commonprefix)

def is_path_prefix(prefix, path):
    return prefix == os.sep.join(os.path.commonprefix(list(map(splitpath, [prefix, path]))))

def group_tracks_by_id3_template(tracks, template):
    grouped_tracks_dict = {}
    template_vars = set(re.findall(r'{.*?}', template))
    for track in tracks:
        try:
            id3_dict = mutagen.File(track, easy=True)
        except:
            id3_dict = {}

        key = template
        single_var_present = False
        for var in template_vars:
            val = id3_dict.get(var[1:-1], [''])[0]
            if len(val) > 0:
                single_var_present = True
            key = key.replace(var, val)

        if single_var_present:
            if key not in grouped_tracks_dict:
                grouped_tracks_dict[key] = []
            grouped_tracks_dict[key].append(track)

    return sorted(grouped_tracks_dict.items())

def estimate_track_loudness_db(path, max_seconds=45):
    """估算音轨响度（dBFS），用于自动音量均衡。"""
    input_container = None
    try:
        input_container = av.open(path)
        audio_stream = input_container.streams.audio[0]

        sample_rate = audio_stream.rate or 44100
        max_samples = int(max_seconds * sample_rate * 2)

        sum_squares = 0.0
        sample_count = 0

        for frame in input_container.decode(audio=0):
            try:
                data = frame.to_ndarray()
            except Exception:
                continue

            if data is None:
                continue

            if hasattr(data, "size") and data.size == 0:
                continue

            normalized = data.astype('float64', copy=False).ravel()
            kind = data.dtype.kind

            if kind in ('i', 'u'):
                bits = data.dtype.itemsize * 8
                if kind == 'i':
                    max_abs = float(1 << (bits - 1))
                else:
                    max_abs = float((1 << bits) - 1)
                if max_abs <= 0:
                    continue
                normalized = normalized / max_abs

            sum_squares += float((normalized * normalized).sum())
            sample_count += int(normalized.size)

            if sample_count >= max_samples:
                break

        if sample_count == 0:
            return None

        rms = math.sqrt(sum_squares / sample_count)
        if rms <= 1e-12:
            return -120.0

        return 20.0 * math.log10(rms)
    except Exception:
        return None
    finally:
        if input_container:
            try:
                input_container.close()
            except Exception:
                pass

class Text2Speech(object):
    """使用 Edge TTS 生成语音"""
    
    # 默认使用中文女声
    DEFAULT_VOICE = "zh-CN-XiaoxiaoNeural"
    
    @staticmethod
    def check_support():
        """检查 edge-tts 是否可用"""
        if edge_tts is None:
            print("错误: 未安装 edge-tts。请运行: pip install edge-tts")
            return False
        return True

    @staticmethod
    def text2speech(out_wav_path, text):
        """使用 edge-tts 生成语音文件"""
        # 如果文件已存在则跳过
        if os.path.isfile(out_wav_path):
            verboseprint("使用现有的", out_wav_path)
            return True

        # 确保是字符串
        if not isinstance(text, str):
            text = str(text, 'utf-8')
        
        # 生成临时 MP3 文件，然后转为 WAV
        tmp_mp3 = tempfile.NamedTemporaryFile(suffix=".mp3", delete=False)
        tmp_mp3.close()
        
        try:
            # 使用 asyncio 运行 edge-tts
            asyncio.run(Text2Speech._generate_tts(tmp_mp3.name, text))
            
            # 使用 pyav 将 MP3 转换为 WAV (iPod 需要 WAV 格式)
            Text2Speech._convert_mp3_to_wav(tmp_mp3.name, out_wav_path)
            return True
        except Exception as e:
            print(f"语音生成失败: {e}")
            return False
        finally:
            # 清理临时文件
            if os.path.exists(tmp_mp3.name):
                os.remove(tmp_mp3.name)
    
    @staticmethod
    async def _generate_tts(output_path, text):
        """异步生成 TTS 音频"""
        communicate = edge_tts.Communicate(text, Text2Speech.DEFAULT_VOICE)
        await communicate.save(output_path)
    
    @staticmethod
    def _convert_mp3_to_wav(mp3_path, wav_path):
        """使用 pyav 将 MP3 转换为 WAV"""
        input_container = av.open(mp3_path)
        output_container = av.open(wav_path, 'w')
        
        # 获取输入音频流
        input_stream = input_container.streams.audio[0]
        
        # 创建输出音频流 (PCM 16-bit)
        output_stream = output_container.add_stream(
            'pcm_s16le', 
            rate=input_stream.rate,
            layout=input_stream.layout
        )
        
        # 转码
        for frame in input_container.decode(audio=0):
            frame.pts = None
            for packet in output_stream.encode(frame):
                output_container.mux(packet)
        
        # 刷新编码器
        for packet in output_stream.encode():
            output_container.mux(packet)
        
        input_container.close()
        output_container.close()


class Record(object):

    def __init__(self, parent):
        self.parent = parent
        self._struct = collections.OrderedDict([])
        self._fields = {}
        self.track_voiceover = parent.track_voiceover
        self.playlist_voiceover = parent.playlist_voiceover
        self.rename = parent.rename
        self.trackgain = parent.trackgain

    def __getitem__(self, item):
        if item not in self._struct:
            raise KeyError
        return self._fields.get(item, self._struct[item][1])

    def __setitem__(self, item, value):
        self._fields[item] = value

    def construct(self):
        chunks = []
        for i in list(self._struct.keys()):
            (fmt, default) = self._struct[i]
            chunks.append(struct.pack("<" + fmt, self._fields.get(i, default)))
        return b"".join(chunks)

    def text_to_speech(self, text, dbid, playlist = False):
        if self.track_voiceover and not playlist or self.playlist_voiceover and playlist:
            # Create the voiceover wav file
            fn = ''.join(format(x, '02x') for x in reversed(dbid))
            path = os.path.join(self.base, "iPod_Control", "Speakable", "Tracks" if not playlist else "Playlists", fn + ".wav")
            return Text2Speech.text2speech(path, text)
        return False

    def path_to_ipod(self, filename):
        abs_filename = os.path.abspath(filename)
        if not is_subpath(abs_filename, self.base):
            raise IOError("Cannot get Ipod filename, since file is outside the IPOD path")
        return "/" + os.path.relpath(abs_filename, self.base).replace(os.path.sep, "/")

    def ipod_to_path(self, ipodname):
        return os.path.abspath(os.path.join(self.base, os.path.sep.join(ipodname.split("/"))))

    @property
    def shuffledb(self):
        parent = self.parent
        while parent.__class__ != Shuffler:
            parent = parent.parent
        return parent

    @property
    def base(self):
        return self.shuffledb.path

    @property
    def tracks(self):
        return self.shuffledb.tracks

    @property
    def albums(self):
        return self.shuffledb.albums

    @property
    def artists(self):
        return self.shuffledb.artists

    @property
    def lists(self):
        return self.shuffledb.lists

class TunesSD(Record):
    def __init__(self, parent):
        Record.__init__(self, parent)
        self.track_header = TrackHeader(self)
        self.play_header = PlaylistHeader(self)
        self._struct = collections.OrderedDict([
                           ("header_id", ("4s", b"bdhs")), # shdb
                           ("unknown1", ("I", 0x02000003)),
                           ("total_length", ("I", 64)),
                           ("total_number_of_tracks", ("I", 0)),
                           ("total_number_of_playlists", ("I", 0)),
                           ("unknown2", ("Q", 0)),
                           ("max_volume", ("B", 0)),
                           ("voiceover_enabled", ("B", int(self.track_voiceover))),
                           ("unknown3", ("H", 0)),
                           ("total_tracks_without_podcasts", ("I", 0)),
                           ("track_header_offset", ("I", 64)),
                           ("playlist_header_offset", ("I", 0)),
                           ("unknown4", ("20s", b"\x00" * 20)),
                                               ])

    def construct(self):
        # The header is a fixed length, so no need to calculate it
        self.track_header.base_offset = 64
        track_header = self.track_header.construct()

        # The playlist offset will depend on the number of tracks
        self.play_header.base_offset = self.track_header.base_offset + len(track_header)
        play_header = self.play_header.construct(self.track_header.tracks)
        self["playlist_header_offset"] = self.play_header.base_offset

        self["total_number_of_tracks"] = self.track_header["number_of_tracks"]
        self["total_tracks_without_podcasts"] = self.track_header["number_of_tracks"]
        self["total_number_of_playlists"] = self.play_header["number_of_playlists"]

        output = Record.construct(self)
        return output + track_header + play_header

class TrackHeader(Record):
    def __init__(self, parent):
        self.base_offset = 0
        Record.__init__(self, parent)
        self._struct = collections.OrderedDict([
                           ("header_id", ("4s", b"hths")), # shth
                           ("total_length", ("I", 0)),
                           ("number_of_tracks", ("I", 0)),
                           ("unknown1", ("Q", 0)),
                                             ])

    def construct(self):
        self["number_of_tracks"] = len(self.tracks)
        self["total_length"] = 20 + (len(self.tracks) * 4)
        header_output = Record.construct(self)

        # Construct the underlying tracks
        offsets = bytearray()
        track_chunks = []
        track_chunk_len = 0
        for i in self.tracks:
            track = Track(self)
            verboseprint("[*] 添加曲目", i)
            track.populate(i)
            offsets.extend(struct.pack("I", self.base_offset + self["total_length"] + track_chunk_len))
            track_bytes = track.construct()
            track_chunks.append(track_bytes)
            track_chunk_len += len(track_bytes)
        return header_output + bytes(offsets) + b"".join(track_chunks)

class Track(Record):

    def __init__(self, parent):
        Record.__init__(self, parent)
        self._struct = collections.OrderedDict([
                           ("header_id", ("4s", b"rths")), # shtr
                           ("header_length", ("I", 0x174)),
                           ("start_at_pos_ms", ("I", 0)),
                           ("stop_at_pos_ms", ("I", 0)),
                           ("volume_gain", ("I", int(self.trackgain))),
                           ("filetype", ("I", 1)),
                           ("filename", ("256s", b"\x00" * 256)),
                           ("bookmark", ("I", 0)),
                           ("dontskip", ("B", 1)),
                           ("remember", ("B", 0)),
                           ("unintalbum", ("B", 0)),
                           ("unknown", ("B", 0)),
                           ("pregap", ("I", 0x200)),
                           ("postgap", ("I", 0x200)),
                           ("numsamples", ("I", 0)),
                           ("unknown2", ("I", 0)),
                           ("gapless", ("I", 0)),
                           ("unknown3", ("I", 0)),
                           ("albumid", ("I", 0)),
                           ("track", ("H", 1)),
                           ("disc", ("H", 0)),
                           ("unknown4", ("Q", 0)),
                           ("dbid", ("8s", 0)),
                           ("artistid", ("I", 0)),
                           ("unknown5", ("32s", b"\x00" * 32)),
                           ])

    def populate(self, filename):
        self["filename"] = self.path_to_ipod(filename).encode('utf-8')

        auto_gain = self.shuffledb.track_gain_overrides.get(filename)
        if auto_gain is not None:
            self["volume_gain"] = auto_gain

        if os.path.splitext(filename)[1].lower() in (".m4a", ".m4b", ".m4p", ".aa"):
            self["filetype"] = 2

        text = os.path.splitext(os.path.basename(filename))[0]

        # Try to get album and artist information with mutagen
        if mutagen:
            audio = None
            try:
                audio = mutagen.File(filename, easy = True)
            except:
                print("调用 mutagen 时出错。可能是无效的文件名/ID3标签（文件名中包含连字符？）")
            if audio:
                # Note: Rythmbox IPod plugin sets this value always 0.
                self["stop_at_pos_ms"] = int(audio.info.length * 1000)

                artist = audio.get("artist", ["Unknown"])[0]
                artist_index = self.shuffledb.artist_index.get(artist)
                if artist_index is None:
                    artist_index = len(self.artists)
                    self.shuffledb.artist_index[artist] = artist_index
                    self.artists.append(artist)
                self["artistid"] = artist_index

                album = audio.get("album", ["Unknown"])[0]
                album_index = self.shuffledb.album_index.get(album)
                if album_index is None:
                    album_index = len(self.albums)
                    self.shuffledb.album_index[album] = album_index
                    self.albums.append(album)
                self["albumid"] = album_index

                if audio.get("title", "") and audio.get("artist", ""):
                    text = " - ".join(audio.get("title", "") + audio.get("artist", ""))

        # Handle the VoiceOverData
        if isinstance(text, str):
            text = text.encode('utf-8', 'ignore')
        self["dbid"] = hashlib.md5(text).digest()[:8]
        self.text_to_speech(text, self["dbid"])

class PlaylistHeader(Record):
    def __init__(self, parent):
        self.base_offset = 0
        Record.__init__(self, parent)
        self._struct = collections.OrderedDict([
                          ("header_id", ("4s", b"hphs")), #shph
                          ("total_length", ("I", 0)),
                          ("number_of_playlists", ("I", 0)),
                          ("number_of_non_podcast_lists", ("2s", b"\xFF\xFF")),
                          ("number_of_master_lists", ("2s", b"\x01\x00")),
                          ("number_of_non_audiobook_lists", ("2s", b"\xFF\xFF")),
                          ("unknown2", ("2s", b"\x00" * 2)),
                                              ])

    def construct(self, tracks):
        # Build the master list
        masterlist = Playlist(self)
        verboseprint("[+] Adding master playlist")
        track_positions = {track: index for index, track in enumerate(tracks)}
        masterlist.set_master(tracks)
        chunks = [masterlist.construct(tracks, track_positions)]

        # Build all the remaining playlists
        playlistcount = 1
        for i in self.lists:
            playlist = Playlist(self)
            verboseprint("[+] Adding playlist", (i[0] if type(i) == type(()) else i))
            playlist.populate(i)
            construction = playlist.construct(tracks, track_positions)
            if playlist["number_of_songs"] > 0:
                playlistcount += 1
                chunks.append(construction)
            else:
                print("错误: 播放列表不包含任何曲目。跳过播放列表。")

        self["number_of_playlists"] = playlistcount
        self["total_length"] = 0x14 + (self["number_of_playlists"] * 4)
        # Start the header

        output = bytearray(Record.construct(self))
        offset = self.base_offset + self["total_length"]

        for chunk in chunks:
            output.extend(struct.pack("I", offset))
            offset += len(chunk)

        return bytes(output) + b"".join(chunks)

class Playlist(Record):
    def __init__(self, parent):
        self.listtracks = []
        Record.__init__(self, parent)
        self._struct = collections.OrderedDict([
                          ("header_id", ("4s", b"lphs")), # shpl
                          ("total_length", ("I", 0)),
                          ("number_of_songs", ("I", 0)),
                          ("number_of_nonaudio", ("I", 0)),
                          ("dbid", ("8s", b"\x00" * 8)),
                          ("listtype", ("I", 2)),
                          ("unknown1", ("16s", b"\x00" * 16))
                                              ])

    def set_master(self, tracks):
        # By default use "All Songs" builtin voiceover (dbid all zero)
        # Else generate alternative "All Songs" to fit the speaker voice of other playlists
        if self.playlist_voiceover:
            self["dbid"] = hashlib.md5(b"masterlist").digest()[:8]
            self.text_to_speech("All songs", self["dbid"], True)
        self["listtype"] = 1
        self.listtracks = tracks

    def populate_m3u(self, data):
        listtracks = []
        for i in data:
            if not i.startswith("#"):
                path = i.strip()
                if self.rename:
                    path = validate_unicode(path)
                listtracks.append(path)
        return listtracks

    def populate_pls(self, data):
        sorttracks = []
        for i in data:
            dataarr = i.strip().split("=", 1)
            if dataarr[0].lower().startswith("file"):
                num = int(dataarr[0][4:])
                filename = urllib.parse.unquote(dataarr[1]).strip()
                if filename.lower().startswith('file://'):
                    filename = filename[7:]
                if self.rename:
                    filename = validate_unicode(filename)
                sorttracks.append((num, filename))
        listtracks = [ x for (_, x) in sorted(sorttracks) ]
        return listtracks

    def populate_directory(self, playlistpath, recursive = True):
        # Add all tracks inside the folder and its subfolders recursively.
        # Folders containing no music and only a single Album
        # would generate duplicated playlists. That is intended and "wont fix".
        # Empty folders (inside the music path) will generate an error -> "wont fix".
        listtracks = []
        for (dirpath, dirnames, filenames) in os.walk(playlistpath):
            dirnames.sort()
            relpath = os.path.relpath(dirpath, playlistpath)
            rel_parts = [] if relpath == "." else relpath.split(os.path.sep)
            hidden_dir = any(part.startswith(".") for part in rel_parts)

            # Ignore any hidden directories
            if not hidden_dir:
                for filename in sorted(filenames, key = lambda x: x.lower()):
                    # Only add valid music files to playlist
                    if os.path.splitext(filename)[1].lower() in music_ext:
                        fullPath = os.path.abspath(os.path.join(dirpath, filename))
                        listtracks.append(fullPath)
            if not recursive:
                break
        return listtracks

    def remove_relatives(self, relative, filename):
        base = os.path.dirname(os.path.abspath(filename))
        if not os.path.exists(relative):
            relative = os.path.join(base, relative)
        fullPath = relative
        return fullPath

    def populate(self, obj):
        # Create a playlist of the folder and all subfolders
        if type(obj) == type(()):
            self.listtracks = obj[1]
            text = obj[0]
        else:
            filename = obj
            if os.path.isdir(filename):
                self.listtracks = self.populate_directory(filename)
                text = os.path.splitext(os.path.basename(filename))[0]
            else:
                # Read the playlist file
                with open(filename, 'r', encoding='utf-8-sig', errors='ignore') as f:
                    data = f.readlines()

                extension = os.path.splitext(filename)[1].lower()
                if extension == '.pls':
                    self.listtracks = self.populate_pls(data)
                elif extension == '.m3u':
                    self.listtracks = self.populate_m3u(data)
                else:
                    raise

                # Ensure all paths are not relative to the playlist file
                for i in range(len(self.listtracks)):
                    self.listtracks[i] = self.remove_relatives(self.listtracks[i], filename)
                text = os.path.splitext(os.path.basename(filename))[0]

        # Handle the VoiceOverData
        self["dbid"] = hashlib.md5(text.encode('utf-8')).digest()[:8]
        self.text_to_speech(text, self["dbid"], True)

    def construct(self, tracks, track_positions=None):
        self["total_length"] = 44 + (4 * len(self.listtracks))
        self["number_of_songs"] = 0

        if track_positions is None:
            track_positions = {track: index for index, track in enumerate(tracks)}

        chunks = bytearray()
        for i in self.listtracks:
            path = self.ipod_to_path(i)
            position = track_positions.get(path)
            if position is None:
                print("错误: 无法找到曲目 \"" + path + "\"。")
                print("也许这是一个无效的 FAT 文件系统名称。请修复您的播放列表。跳过曲目。")
            else:
                chunks.extend(struct.pack("I", position))
                self["number_of_songs"] += 1
        self["number_of_nonaudio"] = self["number_of_songs"]

        output = Record.construct(self)
        return output + bytes(chunks)

class Shuffler(object):
    def __init__(self, path, track_voiceover=False, playlist_voiceover=False, rename=False, trackgain=0, auto_track_gain=False, auto_dir_playlists=None, auto_id3_playlists=None):
        self.path = os.path.abspath(path)
        self.tracks = []
        self.track_set = set()
        self.track_gain_overrides = {}
        self.albums = []
        self.album_index = {}
        self.artists = []
        self.artist_index = {}
        self.lists = []
        self.tunessd = None
        self.track_voiceover = track_voiceover
        self.playlist_voiceover = playlist_voiceover
        self.rename = rename
        self.trackgain = trackgain
        self.auto_track_gain = auto_track_gain
        self.auto_dir_playlists = auto_dir_playlists
        self.auto_id3_playlists = auto_id3_playlists

    def build_auto_track_gains(self):
        print("正在分析曲目响度并计算自动增益...")

        loudness_map = {}
        max_workers = min(os.cpu_count() or 4, 4)
        total = len(self.tracks)
        completed = 0

        with ThreadPoolExecutor(max_workers=max_workers) as executor:
            future_to_track = {
                executor.submit(estimate_track_loudness_db, track): track
                for track in self.tracks
            }

            for future in as_completed(future_to_track):
                track = future_to_track[future]
                loudness_db = None
                try:
                    loudness_db = future.result()
                except Exception:
                    loudness_db = None

                if loudness_db is not None:
                    loudness_map[track] = loudness_db

                completed += 1
                progress = completed / total * 100 if total else 100
                print(f"\r正在分析: [{completed}/{total}] {progress:.1f}%", end="", flush=True)

        print()

        if not loudness_map:
            print("警告: 未能分析任何曲目的响度，自动音量均衡已跳过。")
            return

        reference_loudness = max(loudness_map.values())

        for track, loudness_db in loudness_map.items():
            gain_value = int(round(reference_loudness - loudness_db))
            gain_value = max(0, min(gain_value, 99))
            self.track_gain_overrides[track] = gain_value

        print(
            "自动音量均衡完成: 已为 {0}/{1} 首曲目写入增益（参考响度 {2:.2f} dBFS）。".format(
                len(self.track_gain_overrides),
                len(self.tracks),
                reference_loudness,
            )
        )

    def initialize(self):
      # remove existing voiceover files (they are either useless or will be overwritten anyway)
      for dirname in ('iPod_Control/Speakable/Playlists', 'iPod_Control/Speakable/Tracks'):
          shutil.rmtree(os.path.join(self.path, dirname), ignore_errors=True)
      for dirname in ('iPod_Control/iTunes', 'iPod_Control/Music', 'iPod_Control/Speakable/Playlists', 'iPod_Control/Speakable/Tracks'):
          make_dir_if_absent(os.path.join(self.path, dirname))

    def dump_state(self):
        print("Shuffle 数据库状态")
        print("Tracks", self.tracks)
        print("Albums", self.albums)
        print("Artists", self.artists)
        print("Playlists", self.lists)

    def populate(self):
        self.tunessd = TunesSD(self)
        speakable_root = os.path.join(self.path, "iPod_Control", "Speakable")
        music_root = os.path.join(self.path, "iPod_Control", "Music")
        
        # 第一遍：收集所有文件，分类 FLAC 和其他音频文件
        flac_files = []
        other_audio_files = []
        
        for (dirpath, dirnames, filenames) in os.walk(self.path):
            dirnames.sort()
            relpath = os.path.relpath(dirpath, self.path)
            rel_parts = [] if relpath == "." else relpath.split(os.path.sep)
            hidden_dir = any(part.startswith(".") for part in rel_parts)

            # Ignore the speakable directory and any hidden directories
            if not is_subpath(dirpath, speakable_root) and not hidden_dir:
                for filename in sorted(filenames, key = lambda x: x.lower()):
                    # Ignore hidden files
                    if not filename.startswith("."):
                        fullPath = os.path.abspath(os.path.join(dirpath, filename))
                        ext = os.path.splitext(filename)[1].lower()
                        
                        if ext == ".flac":
                            flac_files.append(fullPath)
                        elif ext in music_ext:
                            other_audio_files.append(fullPath)
                        
                        if ext in (".pls", ".m3u"):
                            self.lists.append(fullPath)

            # Create automatic playlists in music directory.
            # Ignore the (music) root and any hidden directories.
            if self.auto_dir_playlists and is_subpath(dirpath, music_root) and dirpath != music_root and not hidden_dir:
                # Only go to a specific depth. -1 is unlimted, 0 is ignored as there is already a master playlist.
                depth = os.path.relpath(dirpath, music_root).count(os.path.sep) + 1
                if self.auto_dir_playlists < 0 or depth <= self.auto_dir_playlists:
                    self.lists.append(os.path.abspath(dirpath))
        
        # 并发转换 FLAC 文件
        if flac_files:
            print(f"发现 {len(flac_files)} 个 FLAC 文件，开始并发转换...")
            # 使用 CPU 核心数作为最大线程数，但最多 8 个线程
            max_workers = min(os.cpu_count() or 4, 8)
            total_flacs = len(flac_files)
            
            with ThreadPoolExecutor(max_workers=max_workers) as executor:
                # 提交所有转换任务
                future_to_flac = {executor.submit(convert_flac_to_mp3, flac_path): flac_path 
                                  for flac_path in flac_files}
                completed_flacs = 0

                for future in as_completed(future_to_flac):
                    flac_path = future_to_flac[future]
                    try:
                        mp3_path = future.result()
                        if mp3_path and mp3_path not in self.track_set:
                            self.tracks.append(mp3_path)
                            self.track_set.add(mp3_path)
                    except Exception as e:
                        with _print_lock:
                            print(f"\n转换失败 {flac_path}: {e}")

                    completed_flacs += 1
                    progress = completed_flacs / total_flacs * 100
                    print(f"\r正在转换: [{completed_flacs}/{total_flacs}] {progress:.1f}%", end="", flush=True)
            
            print() # 换行
            print(f"FLAC 转换完成！")
        
        # 添加其他音频文件（跳过已有 FLAC 对应的 MP3）
        for fullPath in other_audio_files:
            ext = os.path.splitext(fullPath)[1].lower()
            # 如果是 MP3，检查是否存在对应的 FLAC 源文件
            # 如果存在 FLAC，则跳过此 MP3（它会被上面的 FLAC 逻辑处理）
            if ext == ".mp3":
                flac_source = os.path.splitext(fullPath)[0] + ".flac"
                if os.path.exists(flac_source):
                    continue

            if fullPath not in self.track_set:
                self.tracks.append(fullPath)
                self.track_set.add(fullPath)

        self.tracks.sort(key=lambda x: x.lower())

        if self.auto_track_gain:
            self.build_auto_track_gains()

        if self.auto_id3_playlists is not None:
            if mutagen:
                for grouped_list in group_tracks_by_id3_template(self.tracks, self.auto_id3_playlists):
                    self.lists.append(grouped_list)
            else:
                print("错误: 未找到 mutagen。无法生成 auto-id3-playlists。")
                sys.exit(1)

    def write_database(self):
        print("正在写入数据库。这可能需要一段时间...")
        with open(os.path.join(self.path, "iPod_Control", "iTunes", "iTunesSD"), "wb") as f:
            try:
                f.write(self.tunessd.construct())
            except IOError as e:
                print("I/O 错误({0}): {1}".format(e.errno, e.strerror))
                print("错误: 写入 IPod 数据库失败。")
                sys.exit(1)

        print("数据库写入成功:")
        print("曲目", len(self.tracks))
        print("专辑", len(self.albums))
        print("艺术家", len(self.artists))
        print("播放列表", len(self.lists))

#
# Read all files from the directory
# Construct the appropriate iTunesDB file
# Construct the appropriate iTunesSD file
#   see docs/iTunesSD3gen.md
# Use SVOX pico2wave and RHVoice to produce voiceover data
#

def check_unicode(path):
    ret_flag = False # True if there is a recognizable file within this level
    for item in os.listdir(path):
        if os.path.isfile(os.path.join(path, item)):
            if os.path.splitext(item)[1].lower() in audio_ext+list_ext:
                ret_flag = True
                if raises_unicode_error(item):
                    src = os.path.join(path, item)
                    dest = os.path.join(path, hash_error_unicode(item)) + os.path.splitext(item)[1].lower()
                    print('重命名 %s -> %s' % (src, dest))
                    os.rename(src, dest)
        else:
            ret_flag = (check_unicode(os.path.join(path, item)) or ret_flag)
            if ret_flag and raises_unicode_error(item):
                src = os.path.join(path, item)
                new_name = hash_error_unicode(item)
                dest = os.path.join(path, new_name)
                print('重命名 %s -> %s' % (src, dest))
                os.rename(src, dest)
    return ret_flag

def nonnegative_int(string):
    try:
        intval = int(string)
    except ValueError:
        raise argparse.ArgumentTypeError("'%s' 必须是一个整数" % string)

    if intval < 0 or intval > 99:
        raise argparse.ArgumentTypeError("曲目增益值应在 0-99 范围内")
    return intval

def checkPathValidity(path):
    if not os.path.isdir(path):
        print("寻找 IPod 目录出错。也许它没有连接或挂载？")
        sys.exit(1)

    if not os.access(path, os.W_OK):
        print('无法获得 IPod 目录的写入权限')
        sys.exit(1)

def handle_interrupt(signal, frame):
    print("检测到中断，正在退出...")
    sys.exit(1)

if __name__ == '__main__':
    signal.signal(signal.SIGINT, handle_interrupt)

    parser = argparse.ArgumentParser(description=
    '用于为较新一代 IPod Shuffle 构建曲目和播放列表数据库的 Python 脚本。版本 1.6')

    parser.add_argument('-t', '--track-voiceover', action='store_true',
    help='启用曲目旁白功能')

    parser.add_argument('-p', '--playlist-voiceover', action='store_true',
    help='启用播放列表旁白功能')

    parser.add_argument('-u', '--rename-unicode', action='store_true',
    help='重命名导致 Unicode 错误的文件，将执行所需的最小重命名')

    parser.add_argument('-g', '--track-gain', type=nonnegative_int, default=0,
    help='指定所有曲目的音量增益 (0-99); '
    '0 (默认) 表示没有增益，通常是可以的; '
    '例如 60 即使在最小播放器音量下也会非常响')

    parser.add_argument('--auto-track-gain', action='store_true',
    help='自动音量均衡：直接分析音频内容并按结果写入增益。'
    '分析失败的曲目将回退到 --track-gain。')

    parser.add_argument('-d', '--auto-dir-playlists', type=int, default=None, const=-1, nargs='?',
    help='为 "IPod_Control/Music/" 内的每个文件夹递归生成自动播放列表。'
    '您可以选择限制深度: '
    '0=根目录, 1=艺术家, 2=专辑, n=子文件夹名, 默认=-1 (无限制)。')

    parser.add_argument('-i', '--auto-id3-playlists', type=str, default=None, metavar='ID3_TEMPLATE', const='{artist}', nargs='?',
    help='根据添加到 iPod 的任何音乐的 id3 标签生成自动播放列表。'
    '您可以选择指定一个模板字符串，根据该模板字符串使用 id3 标签生成播放列表。例如 '
    '\'{artist} - {album}\' 将使用艺术家和专辑对将曲目分组到一个播放列表下。'
    '同样 \'{genre}\' 将根据流派标签对曲目进行分组。使用的默认模板是 \'{artist}\'')

    parser.add_argument('-v', '--verbose', action='store_true',
    help='显示数据库生成的详细输出。')

    parser.add_argument('path', help='IPod 根目录的路径')

    result = parser.parse_args()

    # Enable verbose printing if desired
    verboseprint = print if result.verbose else lambda *a, **k: None

    checkPathValidity(result.path)

    if result.rename_unicode:
        check_unicode(result.path)

    if not mutagen:
        print("警告: 未找到 mutagen。数据库将不包含任何专辑或艺术家信息。")

    verboseprint("请求播放列表旁白:", result.playlist_voiceover)
    verboseprint("请求曲目旁白:", result.track_voiceover)
    if (result.track_voiceover or result.playlist_voiceover):
        if not Text2Speech.check_support():
            print("错误: 未找到任何旁白程序。旁白已禁用。")
            result.track_voiceover = False
            result.playlist_voiceover = False
        else:
            verboseprint("旁白可用。")

    shuffle = Shuffler(result.path,
                       track_voiceover=result.track_voiceover,
                       playlist_voiceover=result.playlist_voiceover,
                       rename=result.rename_unicode,
                       trackgain=result.track_gain,
                       auto_track_gain=result.auto_track_gain,
                       auto_dir_playlists=result.auto_dir_playlists,
                       auto_id3_playlists=result.auto_id3_playlists)
    shuffle.initialize()
    shuffle.populate()
    shuffle.write_database()
