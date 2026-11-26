# Architecture

PixelBridge runs entirely on the receiving device. The first working slice opens a PTP/IP session, browses media and commits one original to disk. The physical camera and the bundled responder meet the same TCP contract. SwiftUI Observation and SwiftData set the deployment floor at iOS/iPadOS 17. The shared Xcode scheme includes app, Swift Testing and XCTest UI targets.

## System layers

```mermaid
flowchart TD
    V["Camera · Gallery · Transfers · Settings"] --> VM["Screen view models"]
    VM --> C["ConnectionManager"]
    VM --> T["TransferManager"]
    C --> B["CoreBluetooth"]
    C --> W["Wi-Fi configuration and path monitor"]
    C --> P["CameraTransport / PTPEngine"]
    P --> S["Command and event TCP sockets"]
    S --> D["Physical camera or loopback responder"]
    C --> T
    T --> DB["SwiftData transfer journal"]
    T --> F["Private partial → local original"]
    VM --> PH["User-initiated PhotoKit export"]
    PH --> F
```

## UML components

Mermaid class notation with UML component stereotypes expresses usage and provided interfaces. Multiplicity for persistent entities is specified in the ER diagram.

```mermaid
classDiagram
    class Screens { <<component>> }
    class ConnectionManager { <<component>> }
    class TransferManager { <<component>> }
    class StorageManager { <<component>> }
    class RadioAdapters { <<component>> }
    class PhotoLibraryManager { <<component>> }
    class CameraTransport { <<interface>> }
    class WiFiPathObserving { <<interface>> }
    class PTPEngine { <<component>> }
    class NetworkMonitor { <<component>> }
    Screens ..> ConnectionManager
    Screens ..> PhotoLibraryManager
    ConnectionManager ..> RadioAdapters
    ConnectionManager ..> CameraTransport
    ConnectionManager ..> WiFiPathObserving
    ConnectionManager --> TransferManager
    TransferManager --> StorageManager
    CameraTransport <|.. PTPEngine
    WiFiPathObserving <|.. NetworkMonitor
```

## UML classes

```mermaid
classDiagram
    class CameraViewModel {
      +connect()
    }
    class GalleryViewModel {
      +search
      +files
    }
    class TransferViewModel {
      +retry(item)
      +export(item)
    }
    class SettingsViewModel {
      +forget()
    }
    class ConnectionManager {
      +state
      +connect(source)
      +download(file)
      +disconnect()
    }
    class TransferManager {
      +begin(file, device)
      +append(data)
      +pause(reason)
      +finish()
    }
    class PTPEngine {
      +open(initiator)
      +thumbnail(file)
      +download(file, write)
      +close()
    }
    CameraViewModel --> ConnectionManager
    GalleryViewModel --> ConnectionManager
    TransferViewModel --> ConnectionManager
    SettingsViewModel ..> WiFiManager
    ConnectionManager --> TransferManager
    ConnectionManager ..> PTPEngine
    ConnectionManager --> "0..1" CameraSession
    CameraSession --> "1" CameraDevice
    CameraSession --> "*" CameraStorage
    CameraSession --> "*" MediaFile
    TransferManager --> "0..1" TransferTask
```

## Persistent data model

The diagram defines the normalized target schema. Today SwiftData persists TRANSFER_TASK with a snapshot of camera GUID, storage ID, handle, name, capture time and expected size. The catalog and active session live in memory. TransferHistory currently projects journal rows. AppSettings uses UserDefaults and an optional hotspot password uses device-only Keychain. Introducing separate catalog/history tables will require a migration from these snapshots.

```mermaid
erDiagram
    CAMERA_DEVICE ||--o{ CAMERA_SESSION : opens
    CAMERA_DEVICE ||--o{ CAMERA_STORAGE : contains
    CAMERA_STORAGE ||--o{ MEDIA_FILE : lists
    MEDIA_FILE ||--o{ TRANSFER_TASK : identifies
    TRANSFER_TASK ||--o{ TRANSFER_HISTORY : records
    CAMERA_SESSION ||--o{ TRANSFER_HISTORY : serves
    CAMERA_DEVICE {
      uuid guid PK
      string model
      string firmware
    }
    CAMERA_SESSION {
      uuid id PK
      uuid camera_guid FK
      datetime opened_at
    }
    CAMERA_STORAGE {
      uuid id PK
      uuid camera_guid FK
      int ptp_storage_id
    }
    MEDIA_FILE {
      uuid id PK
      uuid storage_id FK
      int handle
      string filename
      string captured
      int64 bytes
    }
    TRANSFER_TASK {
      uuid id PK
      uuid media_id FK
      int64 expected
      int64 received
      string state
      string local_name
    }
    TRANSFER_HISTORY {
      uuid id PK
      uuid task_id FK
      uuid session_id FK
      datetime timestamp
      string outcome
    }
    APP_SETTINGS {
      string key PK
      string value
    }
```

## BLE pairing

Only discovery and GATT connection ship in the prototype. Nikon authentication and Wi-Fi activation below require per-model evidence.

```mermaid
sequenceDiagram
    actor User
    participant App
    participant CB as CoreBluetooth
    participant Camera
    User->>Camera: Enable pairing mode
    User->>App: Scan for cameras
    App->>CB: Request Bluetooth access and scan
    Camera-->>CB: Advertisement
    CB-->>App: Candidate peripheral
    User->>App: Select camera
    App->>CB: Connect with deadline
    CB->>Camera: Establish GATT link
    alt Link opened
        CB-->>App: Connected
        opt Future verified Nikon pairing adapter
            App->>Camera: Request documented authentication flow
            Camera-->>User: Confirm pairing on device
            Camera-->>App: Authentication outcome
        end
    else Denied or timed out
        CB-->>App: Show error and allow retry
    end
```

## Wi-Fi joining

```mermaid
sequenceDiagram
    actor User
    participant App
    participant OS as iOS
    participant Cam as Camera AP
    User->>Cam: Enable camera Wi-Fi
    alt Already joined in Settings
        User->>App: Enter camera address
    else User enters camera SSID
        App->>OS: Apply joinOnce configuration
        OS->>User: Ask to join
        User-->>OS: Allow or decline
        OS-->>App: Join result
    end
    OS-->>App: Wi-Fi path status
    App->>Cam: Open Wi-Fi-bound local TCP
    Cam-->>App: Protocol handshake result
```

## PTP/IP session

```mermaid
sequenceDiagram
    participant P as PTPEngine
    participant C as Command socket
    participant E as Event socket
    P->>C: InitCommandRequest
    C-->>P: Ack with GUID and connection number
    P->>E: InitEventRequest with connection number
    E-->>P: InitEventAck
    P->>C: OpenSession (transaction 0)
    C-->>P: OK
    par Metadata and original
        P->>C: DeviceInfo, StorageIDs, Handles, ObjectInfo
        C-->>P: Data sets and operation responses
        P->>C: GetObject
        C-->>P: StartData, Data, EndData, OK
    and Event reader
        E-->>P: ProbeRequest
        P->>E: ProbeResponse
    end
```

## Transfer state machine

```mermaid
stateDiagram-v2
    [*] --> Queued
    Queued --> Downloading: open private partial
    Downloading --> Saved: response and file size verified
    Downloading --> Suspended: disconnect or write failure
    Suspended --> Downloading: same object, restart at zero
    Saved --> Failed: local file missing or changed on launch
    Failed --> Downloading: explicit retry
    Saved --> [*]
```

## Loss and recovery

```mermaid
flowchart TD
    A["Wi-Fi path lost or TCP closed"] --> B["Invalidate old session and stop socket readers"]
    B --> C["Close partial and save byte count"]
    C --> D["Preserve independent BLE link if available"]
    D --> E{"Wi-Fi available?"}
    E -->|No| F["Wait for path change"]
    F --> E
    E -->|Yes| G["Reopen both TCP channels with bounded backoff"]
    G --> H{"Responder GUID matches?"}
    H -->|No| I["Require explicit camera selection"]
    H -->|Yes| J{"Card and object identity match?"}
    J -->|No| K["Keep partial and request file selection"]
    J -->|Yes| L["Restart original at byte zero"]
```

The coordinator owns one operation at a time. A generation identifier prevents an old callback from writing to a later transfer. A single idle event reader can run alongside the command transaction. SwiftData is isolated to the main actor. A successful move followed by process termination is reconciled from the actual final file size on the next launch. [Wire limits](protocol.md)
