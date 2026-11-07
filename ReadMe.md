# Smart Task Manager — Lab 2 (Smart Client Mobile Application)

**Course:** CCN10503 Mobile System Development  
**Session:** September 2026  
**Institution:** Management & Science University (MSU) — FISE  
**Lecturer:** Mr. Muhd Iliraimi  
**Student:** Anderson Su Jia Qi (ID: 2102026070120)  
**Submission Date:** 4/12/2026  
**Repository:** https://github.com/Jimbokloop/Lab-2-CCN10503-Mobile-System-Development-

---

## How to Import and Run the Project in Android Studio

Follow these steps to set up the project workspace, resolve all package dependencies, and run the application:

### Step 1: Download the Repository
* **Download ZIP:** Click the green **Code** button at the top of this repository, select **Download ZIP**, and extract the contents to a folder on your computer.

### Step 2: Open the Project in Android Studio
1. Launch **Android Studio**.
2. Click **File** ➔ **Open...** (or select **Open** from the Welcome window).
3. Browse to and select the extracted project directory (`Lab-2-CCN10503-Mobile-System-Development-`).
4. Click **OK** to load the project workspace.

### Step 3: Fetch Dependencies (`flutter pub get`)
> **Important:** Downloaded repositories do not include pre-compiled package caches. Until dependencies are fetched, `.dart` files will display temporary red unresolved import lines.

To install all required packages and resolve the red syntax lines:
1. Open the **Terminal** tab at the bottom of Android Studio (`Alt + F12`).
2. Run:
   ```bash
   flutter pub get
   ```
   *(Alternatively, open `pubspec.yaml` in the editor and click **"Pub get"** on the blue action bar across the top).*
3. Once indexing finishes, all red syntax lines will clear.

---

## Project Overview
The **Smart Task Manager** is a cross-platform mobile application built using **Flutter** and **Dart**. It adopts an **Offline-First, Cloud-Synced** architecture that connects local relational persistence (**SQLite**) with real-time cloud data storage (**Firebase Cloud Firestore**), precision background reminders, and defensive input validation.

---

## Core Features Implemented

1. **Local Relational Persistence (SQLite)**
    - Thread-safe singleton `DatabaseHelper` managing `smart_task.db`.
    - Strongly typed table schema: `id`, `title`, `description`, `isCompleted`, `reminderDateTime`, and `isSynced`.
    - Database schema upgrade hook (`onUpgrade`) preserves user tasks while safely migrating from version 1 to 2.

2. **Real-Time Cloud Synchronization (Cloud Firestore)**
    - Two-way synchronization between local SQLite and remote Cloud Firestore (`tasks` collection).
    - Real-time snapshot streams reflect task additions, modifications, and deletions across devices.

3. **Offline Resilience & Automatic Re-sync**
    - Active network monitoring via `connectivity_plus`.
    - Tasks created or modified offline (e.g., in Airplane Mode) are committed locally with `isSynced = 0`.
    - When network connectivity is restored, `syncUnsyncedTasks()` uploads uncommitted records to Cloud Firestore via `SetOptions(merge: true)` and marks them as synced (`isSynced = 1`).

4. **Scheduled Notifications & Exact Alarms**
    - Implemented via `flutter_local_notifications` and `timezone` to convert schedule times to absolute UTC `TZDateTime`.
    - High-priority notification channels trigger audible alerts and banner notifications even when the application is closed or backgrounded.

5. **Multi-Screen Stack Navigation & Input Validation**
    - Stack-based screen transitions (`Navigator.push`/`pop`) between the task list dashboard and the dedicated task form.
    - Form-level validation prevents empty submissions, supported by contextual warning SnackBars and an Undo feature.

---

## Project Structure

```text
lib/
├── main.dart                  # App entry point, Firebase initialization & theme
├── database_helper.dart       # SQLite singleton database helper & CRUD operations
├── models/
│   └── task_model.dart        # Task data class with SQLite & Firestore map converters
├── screens/
│   ├── task_list_screen.dart  # Main dashboard, summary counters & task list
│   └── task_form_screen.dart  # Dedicated add/edit screen with Date/Time pickers
└── services/
    ├── firebase_service.dart     # Cloud Firestore sync & connectivity listener
    └── notification_service.dart # Local scheduled alarm notification engine
```
