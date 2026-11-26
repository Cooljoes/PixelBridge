# Development roadmap

| Phase | Available in this source tree | Next acceptance gate |
| --- | --- | --- |
| 1 · Connectivity | Foreground BLE name-based discovery and GATT connection, user-approved SSID join or manual Wi-Fi, local TCP command/event channels, device info and Wi-Fi monitoring. | Establish a session on one named camera/firmware offline. Verify denial, timeout, cancel and permission recovery on a physical iPhone. Record Nikon pairing separately. |
| 2 · Media management | Enumerate cards and object handles, read names/sizes/timestamps, show a thumbnail through ImageIO. Bounded to 200 handles. | Compare JPEG, NEF and movie listings with both card slots. Add pagination, camera format mapping and EXIF inspection. |
| 3 · Transfer | Stream one original, progress, throughput, ETA, SwiftData history, private partial, Files export and user-triggered Photos import. | Compare a real JPEG against the card by SHA-256. Repeat for RAW, long movies and multiple queued imports. Verify Photos format support and denial on device. |
| 4 · Advanced connectivity | Wi-Fi path/TCP interruption handling, retained partial and bounded reconnect. Matching transfers restart from byte zero. App-added hotspot can be removed in Settings. | Validate get-partial semantics and >4 GiB metadata, add resumable batch jobs and automatic hotspot exit. Test background/locked states and low-power BLE restoration individually. Research Upload While Off and BLE Wi-Fi wake on specific firmware. |
| 5 · Release | Checked-in Xcode project, unit/integration and UI tests, two-language documentation and third-party notices. | Measure throughput, peak memory, thermal state and energy with real media. Record effective support per firmware and iOS version, sign a device build, then distribute through TestFlight before App Store review. |

## First physical trial

1. Record body model, firmware, iPhone/iPad, OS and card slot. Put one known JPEG on the card and compute its SHA-256 on a computer.
2. Enable the camera’s supported wireless mode. Join the camera network and disable cellular data for the trial. Enter the address from the camera.
3. Record the first successful operation or response code. Compare reported model, object name, timestamp, size and thumbnail against the card.
4. Import the original to Files and compare SHA-256. Repeat with a large JPEG, interrupt during transfer, return to the same Wi-Fi and verify the final hash.
5. Change card or camera and verify that a pending task never attaches to another object. Publish only redacted diagnostics and update the tested capability cells. [Camera profiles](compatibility.md)
