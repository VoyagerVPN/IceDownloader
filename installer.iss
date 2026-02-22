; ============================================================
; IceDownloader Installer
; Run scripts\build-installer.ps1 to rebuild.
; ============================================================



[Setup]
AppName=IceDownloader
AppVersion=1.0
AppPublisher=ᚱ Dev
AppPublisherURL=https://github.com/VoyagerVPN/IceDownloader
AppSupportURL=https://github.com/VoyagerVPN/IceDownloader/issues
AppUpdatesURL=https://github.com/VoyagerVPN/IceDownloader/releases
AppComments=Lightweight YouTube/Video Downloader via yt-dlp
DefaultDirName={autopf}\IceDownloader
DefaultGroupName=IceDownloader
UninstallDisplayIcon={app}\IceDownloader.ico
VersionInfoVersion=1.0
VersionInfoCompany=ᚱ Dev
AppId=IceDownloader-VoyagerVPN
CreateAppDir=yes
UninstallDisplayName=IceDownloader
Compression=lzma2
SolidCompression=yes
OutputDir=userdocs:Inno Setup Examples Output
OutputBaseFilename=IceDownloaderSetup
SetupIconFile=IceDownloader.ico
PrivilegesRequired=admin
WizardStyle=modern

[Tasks]
Name: "startup"; Description: "Запускать при старте Windows"; GroupDescription: "Автозагрузка:";

[Files]
Source: "d:\Pet\yt-dlp-gui\ice-daemon\target\release\ice-daemon.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "d:\Pet\yt-dlp-gui\IceDownloader.ico"; DestDir: "{app}"; Flags: ignoreversion
Source: "d:\Pet\yt-dlp-gui\IceDownloader\*"; DestDir: "{app}\extension"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\IceDownloader"; Filename: "{app}\ice-daemon.exe"; WorkingDir: "{app}"
Name: "{group}\{cm:UninstallProgram,IceDownloader}"; Filename: "{uninstallexe}"

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "IceDownloaderDaemon"; ValueData: """{app}\ice-daemon.exe"""; Tasks: startup; Flags: uninsdeletevalue

[Run]
Filename: "{app}\ice-daemon.exe"; Description: "Запустить IceDownloader Daemon"; Flags: nowait postinstall skipifsilent; WorkingDir: "{app}"

[UninstallRun]
Filename: "taskkill.exe"; Parameters: "/F /IM ice-daemon.exe"; Flags: runhidden

[UninstallDelete]
Type: files; Name: "{app}\yt-dlp.exe"
Type: files; Name: "{app}\update.xml"
Type: files; Name: "{app}\extension.crx"
Type: filesandordirs; Name: "{app}\extension"
Type: dirifempty; Name: "{app}"

[Code]

procedure CurStepChanged(CurStep: TSetupStep);
var
  ErrorCode: Integer;
begin
  if CurStep <> ssPostInstall then Exit;

  // Открываем папку с программой, выделяя папку extension, чтобы юзер мог сразу перетащить ее
  ShellExec('open', 'explorer.exe', '/select,"' + ExpandConstant('{app}\extension') + '"', '', SW_SHOWNORMAL, ewNoWait, ErrorCode);

  MsgBox(
    'IceDownloader успешно установлен!' + #13#10 + #13#10 +
    'Остался последний шаг — добавить расширение в ваш браузер (Chrome, Yandex, Edge, Opera или Brave):' + #13#10 + #13#10 +
    '1. Откройте страницу расширений в браузере (например: chrome://extensions).' + #13#10 +
    '2. Включите "Режим разработчика" ("Developer mode" справа вверху).' + #13#10 +
    '3. Перетащите выделенную папку "extension" из открывшегося окна прямо на страницу расширений в браузере.',
    mbInformation, MB_OK
  );

end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  I: Integer;
  ValueName, ExistingVal: string;
  PolicyPaths: TArrayOfString;
  P: Integer;
begin
  if CurUninstallStep <> usPostUninstall then Exit;

  SetArrayLength(PolicyPaths, 5);
  PolicyPaths[0] := 'SOFTWARE\Policies\Google\Chrome\ExtensionInstallForcelist';
  PolicyPaths[1] := 'SOFTWARE\Policies\Microsoft\Edge\ExtensionInstallForcelist';
  PolicyPaths[2] := 'SOFTWARE\Policies\BraveSoftware\Brave\ExtensionInstallForcelist';
  PolicyPaths[3] := 'SOFTWARE\Policies\Opera Software\Opera stable\ExtensionInstallForcelist';
  PolicyPaths[4] := 'SOFTWARE\Policies\Yandex\YandexBrowser\ExtensionInstallForcelist';

  for P := 0 to High(PolicyPaths) do
  begin
    for I := 1 to 100 do
    begin
      ValueName := IntToStr(I);
      if RegQueryStringValue(HKLM, PolicyPaths[P], ValueName, ExistingVal) then
      begin
        if Pos('afjgggcjlkphobpgpipadjbpnjaaneab', ExistingVal) = 1 then
        begin
          RegDeleteValue(HKLM, PolicyPaths[P], ValueName);
          Break;
        end;
      end
      else
        Break;
    end;
  end;
end;






