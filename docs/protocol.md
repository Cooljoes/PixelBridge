# PTP/IP implementation notes

The prototype accepts an explicit private or link-local IPv4 camera address on Wi-Fi, TCP port 15740. The demo selects an ephemeral loopback port. The app sends no internet probe. A satisfied Wi-Fi path is a routing hint. Success requires two socket acknowledgements, OpenSession and readable camera metadata. [CIPA DC-X005](https://www.cipa.jp/std/documents/e/DC-X005.pdf)

| Stage | Wire contract |
| --- | --- |
| Frame | Little-endian 32-bit total length (includes 8-byte header), 32-bit packet type, payload. Exact reads accumulate fragments. Control frames are bounded. |
| Command initialization | Type 1 carries locally generated persistent initiator GUID, UTF-16LE NUL-terminated name and version 0x00010000. Type 2 supplies the responder GUID and connection number. A rejection ends this attempt. |
| Event initialization | Type 3 sends that connection number on a second TCP connection. Type 4 acknowledges. A dedicated reader consumes events and answers type 13 probes with type 14. |
| OpenSession | Operation 0x1002, transaction 0, session ID 1. Subsequent transaction IDs increase within this session. |
| Metadata | GetDeviceInfo 0x1001 reads model, firmware and advertised operation codes. GetStorageIDs 0x1004, GetObjectHandles 0x1007 and GetObjectInfo 0x1008 enumerate up to 200 handles total. Associations do not appear as files. |
| Preview | GetThumb 0x100A returns bounded data for ImageIO. The original file remains on the camera. |
| Import | GetObject 0x1009. Expect StartData (9), zero or more Data (10), EndData (12) and an OK operation response (7, 0x2001). Check transaction IDs, phase ordering, declared byte counts and ObjectInfo size. Unknown StartData length is supported when ObjectInfo supplies the size. |
| Write and publish | Stream at most 64 KiB per read into a unique private partial. Promote to Documents/Imports only after wire validation, flush and size verification. Source file names are sanitized. A rejected response or interrupted socket leaves the partial outside Imports. |
| Close | Explicit disconnect cancels outstanding work and closes both sockets. Graceful CloseSession and asynchronous PTP cancellation remain interoperability work. |

Control reads are limited to 64 KiB, metadata to 8 MiB and array counts to 500,000. Read/write inactivity expires after 12 seconds. The idle event reader waits for the peer or an observed socket/path failure. This version lists a bounded set and requires a known ObjectInfo size below 0xFFFFFFFF. No operation modifies the card.

## Reconnect and restart

Wi-Fi route loss or socket closure ends the old generation. A new ready Wi-Fi route triggers a bounded reconnect sequence with 1, 2 and 4 second delays. If the GUID changes, the app requests explicit selection. If the original card, handle, filename, length and nonempty capture time still match, the active object restarts from byte zero. A relaunch reconciles SwiftData with actual files and permits manual retry. Files already in Imports remain accessible offline.

A field test should record mode, firmware, endpoint, device OS, operation code and response code. Compare SHA-256 against the memory card for JPEG, NEF and movie trials separately. Keep passwords, serial numbers and private images out of shared diagnostics. [Compatibility profiles](compatibility.md) · [Upstream evidence](research.md)
