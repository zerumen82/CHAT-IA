; LightChat Installer Script for Inno Setup
; Version: 1.1.0
; Date: 15/02/2026
; Incluye instalación automática de Python y vLLM

#define ProjectRoot ".."

[Setup]
AppId={{8F3D9A7E-5B4C-4E8F-A1D2-3C5B7E9F0A1B}
AppName=LightChat
AppVersion=1.1.0
AppVerName=LightChat 1.1.0
AppPublisher=LightChat
AppPublisherURL=https://github.com/lightchat
AppSupportURL=https://github.com/lightchat
AppUpdatesURL=https://github.com/lightchat
DefaultDirName={autopf}\LightChat
DefaultGroupName=LightChat
AllowNoIcons=yes
OutputDir={#ProjectRoot}\dist
OutputBaseFilename=LightChat-Setup-1.1.0
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
UninstallDisplayIcon={app}\lightchat.exe
UninstallDisplayName=LightChat
VersionInfoVersion=1.1.0
VersionInfoCompany=LightChat
VersionInfoDescription=LightChat - Chat ligero con IA local y vLLM integrado
VersionInfoCopyright=Copyright (C) 2026
VersionInfoProductName=LightChat
VersionInfoProductVersion=1.1.0

[Languages]
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
Name: "quicklaunchicon"; Description: "{cm:CreateQuickLaunchIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked; OnlyBelowVersion: 6.1; Check: not IsAdminInstallMode
Name: "installvllm"; Description: "Instalar vLLM automáticamente (requiere conexión a internet)"; GroupDescription: "Instalación automática:"; Flags: checkedonce

[Files]
; Aplicación principal
Source: "{#ProjectRoot}\build\windows\x64\runner\Release\lightchat.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#ProjectRoot}\build\windows\x64\runner\Release\flutter_windows.dll"; DestDir: "{app}"; Flags: ignoreversion

; DLLs de Windows
Source: "{#ProjectRoot}\build\windows\x64\runner\Release\*.dll"; DestDir: "{app}"; Flags: ignoreversion

; Archivos de datos de Flutter
Source: "{#ProjectRoot}\build\windows\x64\runner\Release\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs

; Scripts de instalación
Source: "{#ProjectRoot}\installer\install_vllm.ps1"; DestDir: "{app}\scripts"; Flags: ignoreversion

; Documentación
Source: "{#ProjectRoot}\README.md"; DestDir: "{app}"; DestName: "README.txt"; Flags: ignoreversion skipifsourcedoesntexist
Source: "{#ProjectRoot}\LICENSE"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist

[Dirs]
Name: "{app}\models"; Permissions: users-modify
Name: "{app}\data"; Permissions: users-modify
Name: "{app}\scripts"; Permissions: users-modify
Name: "{localappdata}\LightChat"; Permissions: users-modify
Name: "{localappdata}\LightChat\chat_images"; Permissions: users-modify
Name: "{localappdata}\LightChat\lightchat_models"; Permissions: users-modify

[Icons]
Name: "{group}\LightChat"; Filename: "{app}\lightchat.exe"
Name: "{group}\{cm:ProgramOnTheWeb,LightChat}"; Filename: "https://github.com/lightchat"
Name: "{group}\{cm:UninstallProgram,LightChat}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\LightChat"; Filename: "{app}\lightchat.exe"; Tasks: desktopicon
Name: "{userappdata}\Microsoft\Internet Explorer\Quick Launch\LightChat"; Filename: "{app}\lightchat.exe"; Tasks: quicklaunchicon

[Run]
Filename: "{app}\lightchat.exe"; Description: "{cm:LaunchProgram,LightChat}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}"
Type: filesandordirs; Name: "{localappdata}\LightChat"

[Registry]
; Registrar aplicación en Windows
Root: HKCU; Subkey: "Software\LightChat"; ValueType: string; ValueName: "InstallPath"; ValueData: "{app}"
Root: HKCU; Subkey: "Software\LightChat"; ValueType: string; ValueName: "Version"; ValueData: "1.1.0"
Root: HKCU; Subkey: "Software\LightChat"; ValueType: string; ValueName: "ModelsPath"; ValueData: "{localappdata}\LightChat\lightchat_models"

[Code]
function InitializeSetup(): Boolean;
var
  PythonPath: string;
begin
  Result := True;
  
  // Verificar si Python está instalado
  PythonPath := '';
  if RegQueryStringValue(HKEY_LOCAL_MACHINE, 'SOFTWARE\Python\PythonCore\3.12\InstallPath', '', PythonPath) or
     RegQueryStringValue(HKEY_LOCAL_MACHINE, 'SOFTWARE\Python\PythonCore\3.11\InstallPath', '', PythonPath) or
     RegQueryStringValue(HKEY_LOCAL_MACHINE, 'SOFTWARE\Python\PythonCore\3.10\InstallPath', '', PythonPath) or
     RegQueryStringValue(HKEY_CURRENT_USER, 'SOFTWARE\Python\PythonCore\3.12\InstallPath', '', PythonPath) or
     RegQueryStringValue(HKEY_CURRENT_USER, 'SOFTWARE\Python\PythonCore\3.11\InstallPath', '', PythonPath) or
     RegQueryStringValue(HKEY_CURRENT_USER, 'SOFTWARE\Python\PythonCore\3.10\InstallPath', '', PythonPath) then
  begin
    Log('Python encontrado en: ' + PythonPath);
  end
  else
  begin
    Log('Python no encontrado. Se instalará automáticamente.');
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  DataPath: string;
  ResultCode: Integer;
  InstallVllm: Boolean;
begin
  if CurStep = ssPostInstall then
  begin
    // Crear directorio de datos de usuario
    DataPath := ExpandConstant('{localappdata}\LightChat');
    if not DirExists(DataPath) then
      ForceDirectories(DataPath);
      
    // Crear directorio para imágenes del chat
    DataPath := ExpandConstant('{localappdata}\LightChat\chat_images');
    if not DirExists(DataPath) then
      ForceDirectories(DataPath);
    
    // Crear directorio para modelos
    DataPath := ExpandConstant('{localappdata}\LightChat\lightchat_models');
    if not DirExists(DataPath) then
      ForceDirectories(DataPath);
    
    // Instalar vLLM si está seleccionado
    InstallVllm := WizardIsTaskSelected('installvllm');
    if InstallVllm then
    begin
      // Ejecutar script de instalación de vLLM
      if FileExists(ExpandConstant('{app}\scripts\install_vllm.ps1')) then
      begin
        ShellExec('', 'powershell.exe', 
          '-ExecutionPolicy Bypass -File "' + ExpandConstant('{app}\scripts\install_vllm.ps1') + '"',
          '', SW_SHOW, ewWaitUntilTerminated, ResultCode);
      end;
    end;
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usUninstall then
  begin
    // Preguntar si eliminar datos de usuario
    if MsgBox('¿Desea eliminar todos los datos de usuario, incluyendo modelos descargados?', 
              mbConfirmation, MB_YESNO) = IDYES then
    begin
      DelTree(ExpandConstant('{localappdata}\LightChat'), True, True, True);
    end;
  end;
end;
