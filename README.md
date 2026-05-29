# 🛡️ Expensify - Intelligent Offline Expenditure Tracker

**Expensify** (formerly Expencify) is an offline-first, high-security expenditure management ecosystem. It leverages on-device **Local LLM Inference** to categorize expenses and **Real-time SMS Interception** to automate financial tracking with zero cloud dependencies.

---

## 🚀 Core Technological Pillars

### 🤖 On-Device AI Intelligence (Qwen LLM)
Unlike traditional trackers that rely on cloud-based APIs, Expensify utilizes **Local Large Language Model (LLM)** inference (Qwen/Gemma) to analyze and categorize transaction descriptions.
*   **100% Privacy**: No financial data ever leaves the device.
*   **Semantic Categorization**: Intelligent classification of vague transaction strings into structured budget categories.

### 📩 Automated SMS Pipeline (Broadcast Hooks)
The app implements robust Android **Broadcast Receivers** to instantly intercept bank transaction notifications.
*   **Regex-based Parsing**: Efficient extraction of amounts, vendors, and account details from complex SMS formats.
*   **Background Resilience**: Engineered with background hooks that bypass aggressive Android battery optimizations to ensure zero missed transactions.

### 🔒 Biometric-Locked App Vault (AES-256)
Security is at the heart of Expensify. The application features a secure "App Vault" for sensitive financial summaries.
*   **Encrypted Storage**: Local **SQLite** database secured with AES-256 encryption.
*   **Biometric Authentication**: Integration with Fingerprint/FaceID to unlock the dashboard and vault.
*   **Zero Cloud Footprint**: Absolutely no cloud sync, eliminating the risk of server-side data breaches.

---

## 🛠️ Tech Stack

*   **Framework**: Flutter (Multi-platform)
*   **State Management**: BLoC / Cubit (Event-driven)
*   **Database**: SQLite (Local Persistence)
*   **Security**: Biometric Auth + AES Encryption
*   **AI Engine**: Local LLM Integration (Native C++ bindings for inference)
*   **System Integration**: Android Broadcast Receivers (SMS Interception)

---

## 📂 Project Structure

```text
lib/
├── Application/        # BLoC/Cubit Business Logic
├── Domain/             # Entities, Models, and Failure interfaces
├── Infrastructure/     # SMS Parsing, SQLite Repositories, AI Service
└── Presentation/       # UI Screens (Dashboard, Vault, Settings)
```

---

## ⚙️ Getting Started

### Prerequisites
*   Flutter SDK (3.x+)
*   Android Device (for SMS interception testing)

### Installation
1.  **Clone the repo**:
    ```bash
    git clone https://github.com/nidhin29/expencify.git
    cd expencify
    ```
2.  **Install dependencies**:
    ```bash
    flutter pub get
    ```
3.  **Permissions**:
    The app requires `RECEIVE_SMS` and `READ_SMS` permissions to function. On Android, you must also allow the app to "Ignore Battery Optimizations" for reliable background parsing.

---

## 📄 License

This project is personal and private property.

---

*Developed with ❤️ by [Nidhin V Ninan](https://github.com/nidhin29)*
