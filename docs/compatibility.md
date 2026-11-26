# Nikon capability profiles

The same seven records ship in the [machine-readable capability profiles](../PixelBridge/Resources/NikonProfiles.json), visible in Settings → Camera compatibility. Each row is an independent PixelBridge hardware profile. **Untested** means that a physical camera with a recorded firmware version has yet to complete that operation in this app. The TCP demo has a separate synthetic responder identity.

| Nikon camera | Firmware tested | BLE pairing | Wi-Fi join | PTP/IP session | JPEG | NEF original | Video | Upload While Off | Offset resume |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Z9 | — | Untested | Untested | Untested | Untested | Untested | Untested | Untested | Untested |
| Z8 | — | Untested | Untested | Untested | Untested | Untested | Untested | Untested | Untested |
| Z6 III | — | Untested | Untested | Untested | Untested | Untested | Untested | Untested | Untested |
| Z5 II | — | Untested | Untested | Untested | Untested | Untested | Untested | Untested | Untested |
| Zf | — | Untested | Untested | Untested | Untested | Untested | Untested | Untested | Untested |
| Z50 II | — | Untested | Untested | Untested | Untested | Untested | Untested | Untested | Untested |
| ZR | — | Untested | Untested | Untested | Untested | Untested | Untested | Untested | Untested |

For the first result, add a dated observation under the relevant model with body firmware, iPhone/iPad and OS, camera network menu/mode, direct IP, observed limitation and reproducible steps. Keep BLE discovery, OS pairing, vendor authentication and Wi-Fi wake as separate observations. For media, record card slot, format, byte count, source/destination SHA-256 and behavior after an interruption. For power-off tests, record the queue, switch timing and sleep state. Add separate rows for firmware that behaves differently.

The Nikon Z8 manual documents a vendor feature for certain connection modes. It supplies the basis for a test and does not establish a PixelBridge result. [Nikon camera manual](https://onlinemanual.nikonimglib.com/z8/en/nwm_connect_to_smart_device_358.html) · [Research protocol](research.md)
