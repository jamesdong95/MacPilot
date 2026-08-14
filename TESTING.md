# MacPilot — Manual Test Cases (v0.12.0)

App is installed at `/Applications/MacPilot.app` and the Python core at
`~/.local/bin/macpilot` (0.12.0). To test: **open the app**, click the MacPilot
icon on the Dock if the window does not appear (VDI quirk), then work through
these cases. Expected results are in *italics*.

## 0. Smoke — app launches and connects
1. Open the app.
   - *Window appears at 960×640 with a purple folder icon in the Dock.*
   - *Sidebar shows "Python core connected".*

## 1. Onboarding & indexing
2. First launch → click **Choose folder…** → pick `~/MacPilot-Test-Folder`.
   - *Shows live "Indexed N files…" progress, then "Indexed 11 files…".*
3. Quit and relaunch.
   - *The same folder re-opens automatically (security-scoped bookmark), no re-prompt.*

## 2. Search (FTS5 + prefix + highlight)
4. Type `invoice` → *two PDFs; the term is bolded in the snippet.*
5. Type `insur` (prefix) → *insurance notes still appear.*
6. Click the **Content** filter pill → *only text files shown.*
7. Clear the query → *all indexed files listed.*

## 3. Semantic search (needs embedding provider)
8. First configure: Settings → Local AI → choose **Local (Ollama)** or **Cloud API**
   (base URL + model + key). Save.
9. Toggle **Semantic** in Search (triggers re-index with `--embed`).
10. Type a natural phrase (e.g. "payment for a service").
    - *Files ranked by meaning, not keyword; a tag badge may appear next to each.*

## 4. Auto-tag
11. After semantic re-index, search or list files.
    - *Text files show a semantic tag badge (invoice, contract, notes, …).*

## 5. Suggestions → preview → apply → undo
12. Go to **Suggestions** → *sees move previews (e.g. PDFs → Documents/PDF).*
13. **Preview** a suggestion → *no files change yet.*
14. **Apply** → *files move; Activity records the action.*
15. In **Activity**, **Undo** → *files return to their original location.*

## 6. Safe delete
16. Right-click a file in Search → **Move to Trash** → confirm.
    - *File goes to the macOS Trash; undoable from Activity.*

## 7. Storage report
17. Go to **Storage** → *totals (file count + indexed size), largest files,
    files not touched in 90 days, screenshots.*
18. Click 🗑 on an entry → *moves to Trash, undoable.*

## 8. Duplicates
19. Go to **Duplicates** → *sees the `draft-a.txt` / `draft-b.txt` group (2 copies).*
20. Click **Clean 1** → confirm → *one copy kept, one trashed (undoable).*

## 9. Batch rename
21. **Suggestions** → **Batch rename…** → Find `untitled` → Replace `photo` → Rename.
    - *2 files rename to photo-1.txt / photo-2.txt (individually undoable).*

## 10. Organization rules
22. Settings → **Organization rules** → add `*.png` → `~/MacPilot-Test-Folder/Images`.
    - *Suggestions now favor that rule for PNG files.*

## 11. Summarize (local/cloud LLM)
23. Select a text file → inspector → **Summarize locally**.
    - *Shows a 2–3 sentence summary; if the provider is unreachable, a clear
      "not reachable" message (no crash).*

## 12. Batch summarize
24. In Search with several text files listed → **Summarize** button.
    - *A sheet shows one summary per text file.*

## 13. Saved searches (smart folders)
25. Type a query → click the **bookmark** icon → name it → **Save**.
    - *Appears under "Saved searches" in the sidebar; clicking it re-runs the query;
      right-click → Delete removes it.*

## 14. Keyboard & accessibility
26. Press **⌘,** → *Settings opens.*
27. Press **⌘F** → *search field gains focus.*
28. Tab / arrow keys → *sections and files are navigable; VoiceOver reads labels.*

## 15. Localization
29. Settings → **Language** → pick **Tiếng Việt**.
    - *Sidebar sections and primary buttons switch to Vietnamese.*

## 16. Global hotkey & menu bar
30. Press **⌘⇧Space** from any app (needs Accessibility permission).
    - *MacPilot window opens/raises.*
31. Menu bar extra (sparkle icon) → *shows indexed count + Open / Quit + the hotkey hint.*

## 17. Robustness (edge cases)
32. Index a folder that contains a `.icloud` placeholder file.
    - *The placeholder is skipped (not downloaded / not indexed).*
33. Add an unreadable subfolder (chmod 000).
    - *Indexing completes; the folder is counted as ignored, no crash.*
34. Kill the Python core (`pkill -f macpilot`) then search.
    - *A recoverable "core unavailable" message, not a crash.*

## 18. Diagnostics
35. Trigger an error (e.g. summarize without a provider) → Settings →
    **Open diagnostics log**.
    - *`~/Library/Logs/MacPilot/macpilot.log` opens and contains the error line.*

---

Notes: semantic search, auto-tag, and summarize require a configured LLM
provider. Local Ollama needs `ollama pull qwen2.5:7b` and
`ollama pull nomic-embed-text`; cloud needs a base URL + model + key (key stays
in the macOS Keychain). The app is unsigned — Gatekeeper will prompt on first
launch (right-click → Open). VDI environments may hide the window until you
click the Dock icon.
