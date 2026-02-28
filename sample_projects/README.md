# Sample projects for PreTestflight

Two minimal iOS-style **MVVM** projects used by the [showcase script](../examples/run_showcase.sh) to demonstrate all PreTestflight commands (local and LM).

| Project     | Description |
|------------|-------------|
| **project_a** | Task list: `TaskItem`, `TaskListViewModel`, `TaskListView`, `SettingsView`, `TaskDetailView`, `TaskStorageService`, `SettingsViewModel`, `Date+Format`. `Info.plist`: `UIBackgroundModes` (fetch). |
| **project_b** | Notes: `NoteItem`, `NoteListViewModel`, `NoteListView`, `NoteEditorView`, `ShareSheetView`, `APIClient`, `AppCoordinator`. `ProjectB.entitlements`, `Info.plist` (Photo, Camera, Location, URL scheme), `Base.lproj/Localizable.strings`, `AccentColor.colorset`. |

They are **not** full Xcode projects (no `.xcodeproj`); they are source layouts for reference. The showcase script runs `git init` in each (if needed) so `--save` works, then runs:

1. **Local:** `--save` from project_a  
2. **Local:** `--save` from project_b  
3. **Local:** `--compare-saves` (two zips)  
4. **Local:** `--compare-repos` (project_a vs project_b)  
5. **Local:** `--generate-ui-tests`  
6. **Local:** `--generate-xctests --module ProjectA`  
7. **Local:** `--suggest`  
8. **LM:** `--use-llm --generate-ui-tests`  
9. **LM:** `--use-llm --generate-xctests --module ProjectA`  
10. **LM:** `--use-llm --suggest`  

Run from repo root:

```bash
./examples/run_showcase.sh
```

For commands 8–10, start **LM Studio** with a model and local server (default port 1234). If LM is not available, those steps fall back to stubs or skip.
