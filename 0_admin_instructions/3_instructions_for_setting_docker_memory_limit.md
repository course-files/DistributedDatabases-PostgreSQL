# Setting Docker's Memory Limit

## A. Windows (Docker Desktop with the WSL 2 backend)

With WSL 2, Docker Desktop does not show a memory slider. The limit is set for the WSL 2 virtual machine instead, and it applies to **all** WSL distributions, not only Docker.

> **Important:** Do **not** create the file by right-clicking in File Explorer and choosing *New → Text Document*. That creates a file named `.wslconfig.txt`, and File Explorer hides the `.txt` part by default, so the file looks correct but WSL ignores it. Follow the Notepad steps below instead.

1. Quit Docker Desktop completely: right-click the Docker icon in the system tray (bottom-right of the taskbar) and choose **Quit Docker Desktop**. Closing the window is not enough.

2. Open Notepad: press the `Windows` key, type `Notepad`, and press Enter.

3. Copy the following into Notepad, adjusting the values to suit your machine:

```ini
   [wsl2]
   # Maximum RAM for WSL 2 (and therefore Docker).
   # Use about half to three-quarters of your computer's RAM.
   memory=10GB

   # Optional: number of CPU cores
   processors=2

   # Optional: swap size
   swap=2GB
```

   > Keep each comment on its own line. Do not put a comment on the same line as a setting.

4. Save the file in your user folder with the exact name `.wslconfig`:
   1. In Notepad, click **File → Save as**.
   2. In the **File name** box, type `%UserProfile%` and press Enter. The dialog moves to your user folder (for example `C:\Users\YourName`).
   3. Set **Save as type** to **All files (\*.\*)**.
   4. In the **File name** box, type the name **including the quotation marks**:

   ```text
   ".wslconfig"
   ```

      The quotation marks stop Notepad from adding `.txt` to the name.
   5. Leave **Encoding** as **UTF-8** and click **Save**.

   > If Windows says that `.wslconfig` already exists, click **No**. Open the existing file instead (**File → Open**, go to `%UserProfile%`, set the file type to **All files**) and edit it, so that you do not lose settings already in it.

5. Confirm that the file has the correct name. Open PowerShell and run:

```powershell
   Get-ChildItem -Force $env:USERPROFILE -Filter ".wslconfig*" | Select-Object Name
```

   The output must show `.wslconfig` and nothing else. If it shows `.wslconfig.txt`, rename it:

```powershell
   Rename-Item "$env:USERPROFILE\.wslconfig.txt" ".wslconfig"
```

6. In the same PowerShell window, shut down WSL so the new settings take effect:

```powershell
   wsl --shutdown
```

7. Start Docker Desktop again.

8. Verify the limit:

```powershell
   docker info | findstr "Total Memory"
```

   The value shown will be slightly lower than the one you set (for example, `3.8GiB` for `4GB`). This is normal.

> **Note:** If you do not set `memory`, WSL 2 uses up to 50% of your computer's RAM by default.

## B. Windows (Docker Desktop with the Hyper-V backend) and macOS

Docker Desktop runs a virtual machine whose size you control from the settings.

1. Open Docker Desktop.
2. Go to **Settings → Resources → Advanced**.
3. Move the **Memory** slider to the desired value (for example, 4 GB).
4. Click **Apply & restart**.
5. Verify the limit:

```bash
   docker info | grep "Total Memory"
```

## C. Linux

**If you use Docker Desktop for Linux:** follow Section B. It also runs a virtual machine.

**If you use Docker Engine directly (the usual case on Linux):** there is no virtual machine. Containers share the host's memory and have no overall cap by default, so you limit memory **per container**.

1. Using `docker run`:

```bash
   docker run -d --name my-db --memory=2g --memory-swap=2g postgres:18
```

   `--memory-swap` equal to `--memory` prevents the container from using additional swap.

2. Using Docker Compose (`compose.yaml`):

```yaml
   services:
     db:
       image: postgres:18
       deploy:
         resources:
           limits:
             memory: 2g
```

3. Verify the limit (see the `MEM USAGE / LIMIT` column):

```bash
   docker stats --no-stream
```

> **Note:** The per-container limits in Section C also work on Windows and macOS, inside whatever overall limit Sections A or B set.