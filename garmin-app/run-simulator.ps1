# Script pour lancer l'app Basket dans le simulateur Garmin
$SDK = "C:\Users\manu\AppData\Roaming\Garmin\ConnectIQ\Sdks\connectiq-sdk-win-9.1.0-2026-03-09-6a872a80b\bin"
$PRG = "C:\Users\manu\AppData\Local\Temp\BasketApp\garminapp.prg"

# 1. Copie le .prg dans un chemin sans espace
Copy-Item "C:\Users\manu\Desktop\App garmin\garmin-app\bin\garminapp.prg" $PRG -Force
Write-Host "PRG copié vers $PRG"

# 2. Lance le simulateur en arrière-plan
Write-Host "Lancement du simulateur..."
Start-Process "$SDK\simulator.exe"
Start-Sleep -Seconds 3

# 3. Lance l'app via shell avec la commande 'run'
Write-Host "Chargement de l'app..."
"run `"$PRG`"" | & "$SDK\shell.exe"
