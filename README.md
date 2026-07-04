# SpiceBoard
<img src="Images/SpiceBoard%20Icon-macOS-Default-128x128%401x.png" width="128" alt="SpiceBoard Icon">

**CRITICAL NOTICE: This project was created with AI (Artificial Intelligence), and I, as the author, wrote very little of the actual code myself. It is intended to serve as a solid baseline/foundation for other developers to take over, refine, and fully complete the application. There are still bugs and many usefull features are not or not fully implemented.**

---

SpiceBoard is a modern macOS Usenet client built with Swift, `@Observable` macros, and SwiftUI. It serves as a continuation of the legendary **MacSoup** by Stefan Haller, drawing inspiration specifically from MacSoup's famous graphical thread tracer to visualize discussion structures dynamically.

---

## 🚀 Key Features & Capabilities

### 1. Tri-Pane Layout
* **Unified Usenet Workspace**: A clean, highly optimized multi-pane structure designed exclusively for macOS:
  * **Sidebar**: Subscribed newsgroups with live unread message counts.
  * **Subject Sub-pane**: A multi-column article list showing unread status, subject lines, authors, and dates/ages, complete with resizable columns.
  * **Detail Pane**: Comprehensive message body viewer paired with a graphical thread representation.
* **macOS Integration**: Utilizes SwiftUI's native `NavigationSplitView` to deliver a robust multi-pane sidebar structure, adapting naturally to window resizing.

### 2. Graphical Thread Tracer
* **Visual Conversation Mapping**: An interactive, `Canvas`-based thread tree visualizer that maps article replies using smooth bezier curve segments.
* **Stateful Indicators**: Instantly identify message status:
  * **Unread**: Clearly highlighted state indicators.
  * **Read**: Muted modern accent colors.
  * **References**: Accurately tracks hierarchy levels based on Usenet references.
* **Quick Navigation**: Clicking any node in the visual thread tree immediately selects and displays that article's text in the reader.

### 3. Advanced Composer & Outbox
* **Offline Draft Queue**: Compose new posts, follow-ups, and replies offline. Drafts are queued in a dedicated **Outbox** for manual or batch transmission.
* **Smart Contextual Quoting**: Highlighting any text portion in the reader automatically generates a selectively quoted reply block.
* **ROT13 Support**: Built-in support for ROT13 text encryption/decryption.

### 4. Robust NNTP Sync & Fetch Engine
* **Flexible Article Retrieval (Abruf-Modus)**: Customize your network and bandwidth usage:
  * **Unread Articles**: Syncs only new and unread messages.
  * **Headers Only**: Instant low-bandwidth sync retrieving metadata headers (`XOVER`).
  * **All Articles**: Downloads all threads in the active group.
  * **Max Article Limit**: Define custom batch constraints (e.g., limit to 250 threads) to keep synchronization fast.
* **Offline vs. On-Demand Fetching**: Depending on active preferences, SpiceBoard can download entire article bodies directly during synchronization, or fetch them on-demand as you navigate threads to save offline disk space.
* **Multi-Server Configurations**: Configure multiple NNTP server endpoints with custom hostnames, ports, authentication credentials (username and password), and secure SSL/TLS.

### 5. Detailed Log Viewer & Preferences
* **Log window**: Monitor server handshakes, authentication, NNTP commands (`GROUP`, `XOVER`, `BODY`, `POST`), and transaction results in a real-time, color-coded diagnostic log window.
* **Personal Profile Settings**: Manage your public identity (name, email address, organization headers, and X-Face signature strings).
* **Custom Signature Drawing**: Renders custom face icons directly using high-fidelity vector calculations derived from custom headers!
* **Flexible Preferences Persistence**: Configure custom locations for settings files (`.plist` format) or export configurations.

### 6. Bugs
- X-Face does not really work.
- Writing window does not properly grow when longer texts is written.
  
---

## 📂 Project Structure

* **`SpiceBoardSwiftUIApp.swift`**: Main application entry point initializing core states and system-wide hotkeys/commands.
* **`ContentView.swift`**: The primary UI orchestration view. Manages the tri-pane navigation, resizable panels, search bars, composition views, settings tabs, and native window layouts.
* **`Models.swift`**: Core NNTP business logic. Contains data definitions for `Server`, `Newsgroup`, `Article`, `LogEntry`, and the stateful `UsenetStore` that handles database persistence (`store_state.json`), manual queue flushing, SMTP/NNTP connections, and the full async network client (`SwiftNNTPClient`).
* **`ThreadTreeView.swift`**: Specialized drawing canvas calculating coordinate offsets, hierarchical trees, and visual connectors.
* **`OutboxView.swift`**: An offline draft dashboard displaying queued posts with detailed headers (Subject, Group, Date, References) and manual sync controls.
* **`AboutView.swift`**: Simple application info display highlighting versioning, credits, and historical inspiration references.
* **`NativeWindowManager.swift`**: Window manager layer managing utility HUDs like logs, about screens, and advanced configurations on macOS.

---

## 🛠️ How to use in Xcode

1. Open **Xcode**.
2. Go to **File > New > Project...** and select the **App** template under macOS.
3. Set the project name to `SpiceBoard`.
4. Copy all Swift files (`.swift` files) from this directory into your newly created Xcode project's file explorer.
5. Build and run!

![SpiceBoard](https://github.com/Schnappa/SpiceBoard/blob/main/Images/SpiceBoard%202026-07-04.png)
