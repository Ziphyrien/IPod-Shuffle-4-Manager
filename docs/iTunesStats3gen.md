# iTunesStats

The iTunesStats file contains information about the usage of your iPod. It will be synced back to iTunes to update its stats regarding the playing and skipping of songs.

Here's the general layout of an iTunesSD file:

- Header
  - Track 1 Stats
  - Track 2 Stats
  - ...

## Header

|                 |          |             |
| --------------- | -------- | ----------- |
| **Field**       | **Data** | **Hexdump** |
| Number of Songs | 236      | EC 00 00 00 |
| Unknown         |          | 00 00 00 00 |

## Track X Stats

|                   |            |             |
| ----------------- | ---------- | ----------- |
| **Field**         | **Data**   | **Hexdump** |
| Length of Entry   | 32         | 20 00 00 00 |
| Bookmark Time     | 0x000AF1AA | AA F1 0A 00 |
| Play Count        | 1          | 01 00 00 00 |
| Time of last Play | 0x7C4CE6C7 | 7C 4C E6 C7 |
| Skip Count        | 1          | 01 00 00 00 |
| Time of last Skip | 0xBA4DE6C7 | BA 4D E6 C7 |
| Unknown 1         |            | 00 00 00 00 |
| Unknown 2         |            | 00 00 00 00 |

Original Source: [http://shuffle3db.wikispaces.com/iTunesStats3gen](http://shuffle3db.wikispaces.com/iTunesSD3gen "http://shuffle3db.wikispaces.com/iTunesSD3gen") (expired)
