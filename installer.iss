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

[Code]


var
  BrowserPage: TInputOptionWizardPage;

{ ── Browser detection ────────────────────────────────────── }
function AppPathExists(const ExeName: string): Boolean;
begin
  Result :=
    RegKeyExists(HKCU, 'SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\' + ExeName) or
    RegKeyExists(HKLM, 'SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\' + ExeName);
end;

function ChromeInstalled: Boolean;
begin
  Result := AppPathExists('chrome.exe') or
            RegKeyExists(HKLM, 'SOFTWARE\Google\Chrome') or
            RegKeyExists(HKCU, 'SOFTWARE\Google\Chrome');
end;

function EdgeInstalled: Boolean;
begin
  Result := AppPathExists('msedge.exe') or
            RegKeyExists(HKLM, 'SOFTWARE\Microsoft\EdgeUpdate');
end;

function BraveInstalled: Boolean;
begin
  Result := AppPathExists('brave.exe') or
            RegKeyExists(HKCU, 'SOFTWARE\BraveSoftware\Brave-Browser');
end;

function OperaInstalled: Boolean;
begin
  Result := AppPathExists('opera.exe') or
            RegKeyExists(HKCU, 'SOFTWARE\Opera Software') or
            RegKeyExists(HKLM, 'SOFTWARE\Opera Software');
end;

function YandexInstalled: Boolean;
begin
  Result := AppPathExists('browser.exe') or
            RegKeyExists(HKCU, 'SOFTWARE\YandexBrowser') or
            DirExists(ExpandConstant('{localappdata}\Yandex\YandexBrowser'));
end;

function FirefoxInstalled: Boolean;
begin
  Result := AppPathExists('firefox.exe') or
            RegKeyExists(HKLM, 'SOFTWARE\Mozilla\Mozilla Firefox');
end;

function DuckDuckGoInstalled: Boolean;
begin
  Result := DirExists(ExpandConstant('{localappdata}\Programs\DuckDuckGo'));
end;

{ ── Setup Wizard Hooks ───────────────────────────────────── }
procedure InitializeWizard;
begin
  BrowserPage := CreateInputOptionPage(wpSelectTasks, 'Выбор браузеров', 'В какие браузеры установить расширение?',
    'Отметьте браузеры, в которых вы хотите использовать IceDownloader. По умолчанию отмечены те, что уже найдены в системе.',
    False, False);
  
  BrowserPage.Add('Google Chrome');
  BrowserPage.Add('Microsoft Edge');
  BrowserPage.Add('Brave Browser');
  BrowserPage.Add('Opera');
  BrowserPage.Add('Yandex Browser');

  if ChromeInstalled then BrowserPage.Values[0] := True;
  if EdgeInstalled then BrowserPage.Values[1] := True;
  if BraveInstalled then BrowserPage.Values[2] := True;
  if OperaInstalled then BrowserPage.Values[3] := True;
  if YandexInstalled then BrowserPage.Values[4] := True;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
var
  I: Integer;
begin
  Result := True;
  if CurPageID = BrowserPage.ID then
  begin
    Result := False;
    for I := 0 to 4 do
    begin
      if BrowserPage.Values[I] then
      begin
        Result := True;
        Break;
      end;
    end;
    if not Result then
      MsgBox('Пожалуйста, выберите хотя бы один браузер для установки расширения.', mbError, MB_OK);
  end;
end;

{ ── Post-install hook ────────────────────────────────────── }
procedure CurStepChanged(CurStep: TSetupStep);
var
  WarnMsg: string;
  ErrorCode: Integer;
begin
  if CurStep <> ssPostInstall then Exit;

  if BrowserPage.Values[0] then
  begin
    ShellExec('open', 'chrome.exe', 'chrome://extensions', '', SW_SHOWNORMAL, ewNoWait, ErrorCode);
  end;

  if BrowserPage.Values[1] then
  begin
    ShellExec('open', 'msedge.exe', 'edge://extensions', '', SW_SHOWNORMAL, ewNoWait, ErrorCode);
  end;

  if BrowserPage.Values[2] then
  begin
    ShellExec('open', 'brave.exe', 'brave://extensions', '', SW_SHOWNORMAL, ewNoWait, ErrorCode);
  end;

  if BrowserPage.Values[3] then
  begin
    ShellExec('open', 'opera.exe', 'opera://extensions', '', SW_SHOWNORMAL, ewNoWait, ErrorCode);
  end;

  if BrowserPage.Values[4] then
  begin
    ShellExec('open', 'browser.exe', 'browser://extensions', '', SW_SHOWNORMAL, ewNoWait, ErrorCode);
  end;

  // Открываем папку с расширением, чтобы юзер мог перетащить ее в браузер
  ShellExec('open', ExpandConstant('{app}\extension'), '', '', SW_SHOWNORMAL, ewNoWait, ErrorCode);

  WarnMsg := '';
  if FirefoxInstalled then
    WarnMsg := WarnMsg + #13#10 + '  ! Firefox — не поддерживается (только Chromium)';
  if DuckDuckGoInstalled then
    WarnMsg := WarnMsg + #13#10 + '  ! DuckDuckGo Browser — не поддерживается (только Chromium)';

  MsgBox(
    'IceDownloader успешно установлен!' + #13#10 + #13#10 +
    'Чтобы установить расширение в браузер:' + #13#10 + #13#10 +
    '1. В открывшемся окне браузера включите "Режим разработчика" ("Developer mode" справа вверху).' + #13#10 +
    '2. Перетащите папку "extension" из открывшегося окна прямо в браузер.' + #13#10 + #13#10 +
    WarnMsg,
    mbInformation, MB_OK
  );

end;






