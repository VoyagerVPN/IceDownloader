; ============================================================
; IceDownloader Installer
; Run scripts\build-installer.ps1 to rebuild.
; ============================================================

#define EXTENSION_ID "afjgggcjlkphobpgpipadjbpnjaaneab"

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
PrivilegesRequired=admin
WizardStyle=modern

[Tasks]
Name: "startup"; Description: "Запускать при старте Windows"; GroupDescription: "Автозагрузка:";

[Files]
Source: "d:\Pet\yt-dlp-gui\ice-daemon\target\release\ice-daemon.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "d:\Pet\yt-dlp-gui\IceDownloader.ico"; DestDir: "{app}"; Flags: ignoreversion
Source: "d:\Pet\yt-dlp-gui\IceDownloader.crx"; DestDir: "{app}"; DestName: "extension.crx"; Flags: ignoreversion
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

const
  ExtId = '{#EXTENSION_ID}';

{ ── Path helper: backslash to forward slash ──────────────── }
function ToForwardSlashes(const S: string): string;
var
  i: Integer;
  R: string;
begin
  R := S;
  for i := 1 to Length(R) do
    if R[i] = '\' then R[i] := '/';
  Result := R;
end;

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

{ ── ExtensionInstallForcelist registry helper ─────────────── }
procedure WriteExtensionPolicy(const PolicySubkey: string; const ExtId: string; const UpdateUrl: string);
var
  I: Integer;
  ValueName: string;
  ExistingVal: string;
begin
  for I := 1 to 100 do
  begin
    ValueName := IntToStr(I);
    if not RegQueryStringValue(HKLM, PolicySubkey, ValueName, ExistingVal) then
    begin
      RegWriteStringValue(HKLM, PolicySubkey, ValueName, ExtId + ';' + UpdateUrl);
      Exit;
    end;
    if Pos(ExtId, ExistingVal) = 1 then
    begin
      RegWriteStringValue(HKLM, PolicySubkey, ValueName, ExtId + ';' + UpdateUrl);
      Exit;
    end;
  end;
end;

{ ── Create update.xml manifest ───────────────────────────── }
procedure WriteUpdateXml(const CrxPath: string; const XmlPath: string; const ExtId: string);
var
  CrxUrl, XmlContent: string;
begin
  CrxUrl := 'file:///' + ToForwardSlashes(CrxPath);
  XmlContent :=
    '<?xml version=''1.0'' encoding=''UTF-8''?>' + #13#10 +
    '<gupdate xmlns=''http://www.google.com/update2/response'' protocol=''2.0''>' + #13#10 +
    '  <app appid=''' + ExtId + '''>' + #13#10 +
    '    <updatecheck' + #13#10 +
    '      codebase=''' + CrxUrl + '''' + #13#10 +
    '      version=''1.0.0'' />' + #13#10 +
    '  </app>' + #13#10 +
    '</gupdate>';
  SaveStringToFile(XmlPath, XmlContent, False);
end;

{ ── Post-install hook ────────────────────────────────────── }
procedure CurStepChanged(CurStep: TSetupStep);
var
  CrxPath, XmlPath, UpdateUrl: string;
  InstalledIn, WarnMsg: string;
  HasChromium: Boolean;
  ErrorCode: Integer;
begin
  if CurStep <> ssPostInstall then Exit;

  CrxPath   := ExpandConstant('{app}\extension.crx');
  XmlPath   := ExpandConstant('{app}\update.xml');
  UpdateUrl := 'file:///' + ToForwardSlashes(XmlPath);

  WriteUpdateXml(CrxPath, XmlPath, ExtId);

  InstalledIn := '';
  HasChromium := False;

  if ChromeInstalled then
  begin
    WriteExtensionPolicy('SOFTWARE\Policies\Google\Chrome\ExtensionInstallForcelist', ExtId, UpdateUrl);
    InstalledIn := InstalledIn + #13#10 + '  + Google Chrome';
    HasChromium := True;
  end;

  if EdgeInstalled then
  begin
    WriteExtensionPolicy('SOFTWARE\Policies\Microsoft\Edge\ExtensionInstallForcelist', ExtId, UpdateUrl);
    InstalledIn := InstalledIn + #13#10 + '  + Microsoft Edge';
    HasChromium := True;
  end;

  if BraveInstalled then
  begin
    WriteExtensionPolicy('SOFTWARE\Policies\BraveSoftware\Brave\ExtensionInstallForcelist', ExtId, UpdateUrl);
    InstalledIn := InstalledIn + #13#10 + '  + Brave Browser';
    HasChromium := True;
  end;

  if OperaInstalled then
  begin
    WriteExtensionPolicy('SOFTWARE\Policies\Opera Software\Opera stable\ExtensionInstallForcelist', ExtId, UpdateUrl);
    InstalledIn := InstalledIn + #13#10 + '  + Opera';
    HasChromium := True;
  end;

  if YandexInstalled then
  begin
    WriteExtensionPolicy('SOFTWARE\Policies\Yandex\YandexBrowser\ExtensionInstallForcelist', ExtId, UpdateUrl);
    InstalledIn := InstalledIn + #13#10 + '  + Yandex Browser';
    HasChromium := True;
  end;

  WarnMsg := '';
  if FirefoxInstalled then
    WarnMsg := WarnMsg + #13#10 + '  ! Firefox — не поддерживается (только Chromium)';
  if DuckDuckGoInstalled then
    WarnMsg := WarnMsg + #13#10 + '  ! DuckDuckGo Browser — не поддерживается (только Chromium)';

  if HasChromium then
  begin
    MsgBox(
      'IceDownloader установлен!' + #13#10 + #13#10 +
      'Расширение будет автоматически добавлено в:' + InstalledIn + #13#10 + #13#10 +
      'Перезапустите браузер — расширение установится само.' +
      WarnMsg,
      mbInformation, MB_OK
    );
  end
  else
  begin
    MsgBox(
      'IceDownloader установлен, но совместимый браузер не найден.' + #13#10 + #13#10 +
      'Расширение работает только в Chromium-браузерах:' + #13#10 +
      '  Chrome, Edge, Brave, Opera, Yandex Browser' + #13#10 + #13#10 +
      'После установки браузера откройте раздел расширений,' + #13#10 +
      'включите режим разработчика и загрузите папку:' + #13#10 +
      ExpandConstant('{app}\extension') +
      WarnMsg,
      mbInformation, MB_OK
    );
    ShellExec('open', ExpandConstant('{app}\extension'), '', '', SW_SHOWNORMAL, ewNoWait, ErrorCode);
  end;
end;

{ ── Cleanup on uninstall ─────────────────────────────────── }
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
        if Pos(ExtId, ExistingVal) = 1 then
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


