# PARDEX Windows Paketi

PARDEX, paketlenmiş sürümde Korsanların Hazinesi'ni varsayılan olarak şu yoldan başlatır:

`games\korsanlar\KorsanlarinHazinesi.exe`

Repo içindeki `tools\package_windows.ps1` hem PARDEX'i hem de yan klasördeki `Korsanlarin-Hazinesi` projesini export eder ve bu klasör yapısını otomatik oluşturur.

## Gereksinimler

- Godot 4.7.2
- Godot 4.7.2 Windows export templates
- `Pardex` ve `Korsanlarin-Hazinesi` repolarının varsayılan olarak aynı üst klasörde bulunması

## Paket oluşturma

PARDEX repo kökünde PowerShell açıp:

```powershell
.\tools\package_windows.ps1 -GodotExe "C:\Godot\Godot_v4.7.2-stable_win64.exe"
```

Korsan repo başka bir yerdeyse:

```powershell
.\tools\package_windows.ps1 `
  -GodotExe "C:\Godot\Godot_v4.7.2-stable_win64.exe" `
  -KorsanProject "D:\Projeler\Korsanlarin-Hazinesi"
```

Başarılı olduğunda:

- `dist\PARDEX-Windows\PARDEX.exe`
- `dist\PARDEX-Windows\PARDEX.pck`
- `dist\PARDEX-Windows\games\korsanlar\KorsanlarinHazinesi.exe`
- `dist\PARDEX-Windows\games\korsanlar\KorsanlarinHazinesi.pck`
- `dist\PARDEX-Windows.zip`

oluşturulur.

Dağıtılacak paket `PARDEX-Windows.zip` dosyasıdır. Kullanıcı klasör yapısını değiştirmeden ZIP'i açıp `PARDEX.exe` çalıştırmalıdır.

İstenirse Korsan executable yolu `PARDEX_KORSAN_EXECUTABLE` ortam değişkeniyle override edilebilir.
