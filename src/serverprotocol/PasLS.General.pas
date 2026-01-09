// Pascal Language Server
// Copyright 2020 Arjan Adriaanse
// Copyright 2020 Ryan Joseph

// This file is part of Pascal Language Server.

// Pascal Language Server is free software: you can redistribute it
// and/or modify it under the terms of the GNU General Public License
// as published by the Free Software Foundation, either version 3 of
// the License, or (at your option) any later version.

// Pascal Language Server is distributed in the hope that it will be
// useful, but WITHOUT ANY WARRANTY; without even the implied warranty
// of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with Pascal Language Server.  If not, see
// <https://www.gnu.org/licenses/>.
unit PasLS.General;


{$mode objfpc}{$H+}
{$modeswitch arrayoperators}

interface

uses
  {$ifdef FreePascalMake}
  FPMConfig, FPMUtils,
  {$endif}
  { RTL }
  Classes, URIParser, typinfo,
  { Code Tools }
  CodeToolManager, CodeToolsConfig,
  { Protocol }
  LSP.Base, LSP.Basic, LSP.BaseTypes, LSP.Capabilities, LSP.DocumentSymbol, LSP.General,
  { Utils }
  PasLS.Settings, PasLS.Symbols, PasLS.Commands, PasLS.LazConfig;


Type

  TServerCapabilitiesHelper = class helper for TServerCapabilities
    procedure ApplySettings(settings: TServerSettings);
  end;


  { TLSPInitializeParams }

  TLSPInitializeParams = Class(TInitializeParams)
  Protected
    Function createInitializationOptions: TInitializationOptions; override;
  end;
  { TInitialize }

  TInitialize = class(specialize TLSPRequest<TLSPInitializeParams, TInitializeResult>)
  private
    function CheckProgramSetting: Boolean;
    procedure CollectWorkSpacePaths(WorkspaceFolders: TWorkspaceFolderItems;
      aPaths: TStrings; ExcludeFolders: TStrings);
    procedure DoLog(const Msg: String);
    procedure DoLog(const Fmt: String; const args: array of const);
    procedure DoLog(const Msg: String; aBool: Boolean);
    Function IsPasExt(Const aExtension : String) : Boolean;
    function IsPathExcluded(const aPath: String; ExcludeFolders: TStrings): Boolean;
    procedure SetFPCPaths(Paths, Opts: TStrings; AsUnitPath, asIncludePath: Boolean);
    procedure SetPlatformDefaults(CodeToolsOptions : TCodeToolsOptions);
    procedure ApplyConfigSettings(CodeToolsOptions: TCodeToolsOptions);
    procedure FindPascalSourceDirectories(RootPath: String; Results: TStrings; ExcludeFolders: TStrings);
    Procedure ShowConfigStatus(Params : TInitializeParams; Paths: TStrings; CodeToolsOptions: TCodeToolsOptions);
  Public
    function Process(var Params : TLSPInitializeParams): TInitializeResult; override;
  end;

  { TInitialized }

  TInitialized = class(specialize TLSPNotification<TVoidParams>)
    procedure Process(var Params : TVoidParams); override;
  end;

  { TShutdown }

  TShutdown = class(specialize TLSPRequest<TVoidParams, TLSPStreamable>)
    function Process(var Params : TVoidParams): TLSPStreamable; override;
  end;

  { TExit }

  TExit = class(specialize TLSPNotification<TVoidParams>)
    procedure Process(var Params : TVoidParams); override;
  end;

  { TCancel }

  TCancel = class(specialize TLSPNotification<TCancelParams>)
    procedure Process(var Params : TCancelParams); override;
  end;

implementation

uses
  SysUtils, RegExpr, IdentCompletionTool, DefineTemplates;


const
  kStatusPrefix = '✓ ';
  kFailedPrefix = '⚠️ ';
  kSettingPrefix = '  ► ';
  kEmptyPrefix = '  ';

{ TInitialize }


procedure TInitialize.ApplyConfigSettings(CodeToolsOptions: TCodeToolsOptions);

  function MaybeSet(aValue,aDefault : String) : String;

  begin
    Result:=aValue;
    if Result='' then
      Result:=aDefault;
  end;

Var
  env : TConfigEnvironmentSettings;

begin
  env:=EnvironmentSettings;
  with CodeToolsOptions do
    begin
      FPCPath:=MaybeSet(Env.pp,FPCPath);
      FPCSrcDir:=MaybeSet(Env.fpcDir,FPCSrcDir);
      LazarusSrcDir:=MaybeSet(Env.lazarusDir,LazarusSrcDir);
      TargetOS:=MaybeSet(Env.fpcTarget,TargetOS);
      TargetProcessor:=MaybeSet(Env.fpcTargetCPU,TargetProcessor);
    end;
end;


procedure TInitialize.SetPlatformDefaults(CodeToolsOptions: TCodeToolsOptions);
begin
  // Compile time defaults/
  CodeToolsOptions.TargetOS := {$i %FPCTARGETOS%};
  CodeToolsOptions.TargetProcessor := {$i %FPCTARGETCPU%};

  {$ifdef windows}
  CodeToolsOptions.FPCPath := 'C:\FPC';
  CodeToolsOptions.FPCSrcDir := 'C:\FPC\Src';
  CodeToolsOptions.LazarusSrcDir := 'C:\Lazarus';
  {$endif}

  {$ifdef unix}
  {$ifdef DARWIN}
  CodeToolsOptions.FPCPath := '/usr/local/bin/fpc';
  CodeToolsOptions.FPCSrcDir := '/usr/local/share/fpcsrc';
  CodeToolsOptions.LazarusSrcDir := '/usr/local/share/lazsrc';
  {$else}
  CodeToolsOptions.FPCPath := '/usr/local/bin/fpc';
  CodeToolsOptions.FPCSrcDir := '/usr/local/share/fpcsrc';
  CodeToolsOptions.LazarusSrcDir := '/usr/local/share/lazsrc';
  {$endif}
  {$endif}

end;

{ Find all sub directories which contain Pascal source files }

Function TInitialize.IsPasExt(Const aExtension : String) : Boolean;

var
  E : String;

begin
  E:=LowerCase(aExtension);
  result:=(E = '.pas') or (E = '.pp') or (E = '.inc');
end;


Procedure TInitialize.DoLog(const Msg : String);
begin
  Transport.SendDiagnostic(Msg);
end;


Procedure TInitialize.DoLog(const Fmt : String; Const args : Array of const);
begin
  Transport.SendDiagnostic(Fmt,Args);
end;

Procedure TInitialize.DoLog(const Msg : String; aBool : Boolean);
begin
  Transport.SendDiagnostic(Msg+BoolToStr(aBool,'True','False'));
end;

function TInitialize.IsPathExcluded(const aPath: String; ExcludeFolders: TStrings): Boolean;
var
  ExcludePath: String;
  NormalizedPath: String;
  NormalizedExclude: String;
begin
  Result := False;
  if (ExcludeFolders = nil) or (ExcludeFolders.Count = 0) then
    Exit;

  NormalizedPath := ExcludeTrailingPathDelimiter(aPath);

  for ExcludePath in ExcludeFolders do
    begin
      NormalizedExclude := ExcludeTrailingPathDelimiter(ExcludePath);
      // Check if the path starts with the excluded path
      if (Pos(NormalizedExclude, NormalizedPath) = 1) then
        begin
          Result := True;
          Exit;
        end;
    end;
end;


procedure TInitialize.FindPascalSourceDirectories(RootPath: String; Results: TStrings; ExcludeFolders: TStrings);

var
  Info : TSearchRec;
  havePas : Boolean;
  SubDirPath: String;

begin
  // Skip this directory if it's excluded
  if IsPathExcluded(RootPath, ExcludeFolders) then
    Exit;

  havePas:=False;
  If FindFirst(RootPath+AllFilesMask,faAnyFile,Info)=0 then
    try
      Repeat
        if ((Info.Attr and faDirectory)<>0) and Not ((Info.Name='.') or (Info.Name='..')) then
          begin
            SubDirPath := IncludeTrailingPathDelimiter(RootPath+Info.Name);
            // Only recurse if the subdirectory is not excluded
            if not IsPathExcluded(SubDirPath, ExcludeFolders) then
              FindPascalSourceDirectories(SubDirPath, Results, ExcludeFolders);
          end;
        if IsPasExt(ExtractFileExt(Info.Name)) then
          HavePas:=True;
      until (FindNext(Info)<>0);
    finally
      FindClose(Info)
    end;
  if HavePas then
    if Results.IndexOf(RootPath)=-1 then
      Results.Add(RootPath);
end;

procedure TInitialize.CollectWorkSpacePaths(WorkspaceFolders : TWorkspaceFolderItems; aPaths : TStrings; ExcludeFolders: TStrings);

Var
  Item: TCollectionItem;

begin
  for Item in workspaceFolders do
    FindPascalSourceDirectories(IncludeTrailingPathDelimiter(UriToPath(TWorkspaceFolder(Item).uri)), aPaths, ExcludeFolders);
end;


procedure TInitialize.ShowConfigStatus(Params : TInitializeParams; Paths: TStrings; CodeToolsOptions: TCodeToolsOptions);
var
  aPath, ExcludeList: String;
  I: Integer;
begin
  DoLog( kStatusPrefix+'Server: ' + {$INCLUDE %DATE%});
  DoLog( kStatusPrefix+'Client: ' + Params.clientInfo.name + ' ' + Params.clientInfo.version);

  DoLog( kStatusPrefix+'FPCPath: ' + CodeToolsOptions.FPCPath);
  DoLog( kStatusPrefix+'FPCSrcDir: ' + CodeToolsOptions.FPCSrcDir);
  DoLog( kStatusPrefix+'LazarusSrcDir: ' + CodeToolsOptions.LazarusSrcDir);
  DoLog( kStatusPrefix+'TargetOS: ' + CodeToolsOptions.TargetOS);
  DoLog( kStatusPrefix+'TargetProcessor: '+ CodeToolsOptions.TargetProcessor);

  DoLog( kStatusPrefix+'Working directory: ' + GetCurrentDir);

  if CodeToolsOptions.FPCOptions <> '' then
    DoLog( kStatusPrefix+'FPCOptions: '+CodeToolsOptions.FPCOptions)
  else
    DoLog( kStatusPrefix+'FPCOptions: [unspecified]');

  if ServerSettings.&program <> '' then
    DoLog( kStatusPrefix+'Main program file: ' + ServerSettings.&program);

  if CodeToolsOptions.ProjectDir <> '' then
    DoLog( kStatusPrefix+'ProjectDir: ' + CodeToolsOptions.ProjectDir)
  else
    DoLog( kStatusPrefix+'ProjectDir: [unspecified]');

  {$IFDEF USE_SQLITE}
  if ServerSettings.symbolDatabase <> '' then
    DoLog( kStatusPrefix+'Symbol Database: ' + ServerSettings.symbolDatabase)
  else
    DoLog( kStatusPrefix+'Symbol Database: [unspecified]');
  {$ENDIF}

  // other settings
  DoLog(kStatusPrefix+'Settings:');
  DoLog(kSettingPrefix+'maximumCompletions: %d', [ServerSettings.maximumCompletions]);
  DoLog(kSettingPrefix+'overloadPolicy: %s', [GetEnumName(TypeInfo(TOverloadPolicy),Ord(ServerSettings.overloadPolicy))]);
  DoLog(kSettingPrefix+'insertCompletionsAsSnippets: ', ServerSettings.insertCompletionsAsSnippets);
  DoLog(kSettingPrefix+'insertCompletionProcedureBrackets: ', ServerSettings.insertCompletionProcedureBrackets);
  DoLog(kSettingPrefix+'includeWorkspaceFoldersAsUnitPaths: ', ServerSettings.includeWorkspaceFoldersAsUnitPaths);
  DoLog(kSettingPrefix+'includeWorkspaceFoldersAsIncludePaths: ', ServerSettings.includeWorkspaceFoldersAsIncludePaths);
  DoLog(kSettingPrefix+'checkSyntax: ', ServerSettings.checkSyntax);
  DoLog(kSettingPrefix+'publishDiagnostics: ', ServerSettings.publishDiagnostics);
  DoLog(kSettingPrefix+'workspaceSymbols: ', ServerSettings.workspaceSymbols);
  DoLog(kSettingPrefix+'documentSymbols: ', ServerSettings.documentSymbols);
  DoLog(kSettingPrefix+'minimalisticCompletions: ', ServerSettings.minimalisticCompletions);
  DoLog(kSettingPrefix+'showSyntaxErrors: ', ServerSettings.showSyntaxErrors);
  DoLog(kSettingPrefix+'flatSymbolMode: ', ServerSettings.flatSymbolMode);
  DoLog(kSettingPrefix+'nullDocumentVersion: ', ServerSettings.nullDocumentVersion);
  DoLog(kSettingPrefix+'filterTextOnly: ', ServerSettings.filterTextOnly);

  // Show excludeSymbols
  if ServerSettings.excludeSymbols.Count > 0 then
    begin
      ExcludeList := '';
      for I := 0 to ServerSettings.excludeSymbols.Count - 1 do
        begin
          if ExcludeList <> '' then
            ExcludeList := ExcludeList + ', ';
          ExcludeList := ExcludeList + ServerSettings.excludeSymbols[I];
        end;
      DoLog(kSettingPrefix+'excludeSymbols: [' + ExcludeList + ']');
    end;

  DoLog(kStatusPrefix+'Workspace paths (%d):',[Paths.Count]);
  for aPath in Paths do
    DoLog(kEmptyPrefix+'  %s',[aPath]);
end;


procedure TInitialize.SetFPCPaths(Paths,Opts: TStrings; AsUnitPath,asIncludePath : Boolean);

var
  aPath : String;

begin
  for aPath in Paths do
    begin
      // add directory as search paths
      if AsUnitPath then
        Opts.Add('-Fu'+aPath);
      if AsIncludePath then
        Opts.Add('-Fi'+aPath);
    end;
end;

function TInitialize.CheckProgramSetting : Boolean;

Var
  aPath : String;

begin
  aPath:=ServerSettings.&program;
  if aPath = '' then
    exit(False);
  aPath:=ExpandFileName(aPath);
  Result:=FileExists(aPath);
  if Result then
    ServerSettings.&program := aPath
  else
    begin
      DoLog(kFailedPrefix+'Main program file '+ aPath+ ' can''t be found.');
      ServerSettings.&program := '';
    end;
end;

function TInitialize.Process(var Params : TLSPInitializeParams): TInitializeResult;


var
  Proj, Option, aPath, ConfigPath: String;
  CodeToolsOptions: TCodeToolsOptions;
  re: TRegExpr;
  Macros: TMacroMap;
  Paths: TStringList;
  RootPath,IncludePathTemplate,UnitPathTemplate: TDefineTemplate;
  opt : TServerSettings;

begin
  DoLog('[DEBUG] Initialize.Process checkpoint 1: entry');
  if Params.initializationOptions is TServerSettings then
    Opt:=TServerSettings(Params.initializationOptions)
  else
    Opt:=Nil;
  DoLog('[DEBUG] Initialize.Process checkpoint 2: initializationOptions checked');
  Result := TInitializeResult.Create;
  CodeToolsOptions:=nil;
  Re:=nil;
  Paths:=Nil;
  Macros:=nil;
  try
    DoLog('[DEBUG] Initialize.Process checkpoint 3: creating helper objects');
    Macros := TMacroMap.Create;
    CodeToolsOptions := TCodeToolsOptions.Create;
    re := TRegExpr.Create('^(-(Fu|Fi)+)(.*)$');
    Paths:=TStringList.Create;
    Paths.StrictDelimiter:=True;
    Paths.Delimiter:=';';
    Paths.Sorted:=True;
    Paths.Duplicates:=dupIgnore;

    DoLog('[DEBUG] Initialize.Process checkpoint 4: getting command list');
    Result.capabilities.executeCommandProvider.commands.Clear;
    CommandFactory.GetCommandList(Result.capabilities.executeCommandProvider.commands);

    DoLog('[DEBUG] Initialize.Process checkpoint 5: calling ServerSettings.Assign');
    ServerSettings.Assign(Params.initializationOptions);
    DoLog('[DEBUG] Initialize.Process checkpoint 6: ServerSettings.Assign done');
    PasLS.Settings.ClientInfo.Assign(Params.ClientInfo);

    // Detect hierarchical document symbol support
    DoLog('[DEBUG] Initialize.Process checkpoint 7: detecting client capabilities');
    if Assigned(Params.capabilities) and
       Assigned(Params.capabilities.textDocument) and
       Assigned(Params.capabilities.textDocument.documentSymbol) then
      SetClientCapabilities(Params.capabilities.textDocument.documentSymbol.hierarchicalDocumentSymbolSupport)
    else
      SetClientCapabilities(false);

    // replace macros in server settings
    DoLog('[DEBUG] Initialize.Process checkpoint 8: replacing macros');
    Macros.Add('tmpdir', GetTempDir(true));
    Macros.Add('root', URIToPath(Params.rootUri));

    ServerSettings.ReplaceMacros(Macros);
    DoLog('[DEBUG] Initialize.Process checkpoint 9: macros replaced');

    // set the project directory based on root URI path
    if Params.rootUri <> '' then
      CodeToolsOptions.ProjectDir := URIToPath(Params.rootURI);

    // print the root URI so we know which workspace folder is default
    DoLog(kStatusPrefix+'RootURI: '+Params.rootUri);
    DoLog(kStatusPrefix+'ProjectDir: '+CodeToolsOptions.ProjectDir);

    {
      For more information on CodeTools see:
      https://wiki.freepascal.org/Codetools
    }

    // set some built-in defaults based on platform
    SetPlatformDefaults(CodeToolsOptions);
    ApplyConfigSettings(CodeToolsOptions);

    { Override default settings with environment variables.
      These are the required values which must be set:

      FPCDIR       = path to FPC source directory
      PP           = path of the Free Pascal compiler. For example /usr/bin/ppc386.
      LAZARUSDIR   = path of the lazarus sources
      FPCTARGET    = FPC target OS like linux, win32, darwin
      FPCTARGETCPU = FPC target cpu like i386, x86_64, arm }
    CodeToolsOptions.InitWithEnvironmentVariables;

    DoLog('[DEBUG] Initialize.Process checkpoint 10: guessing codetools config');
    GuessCodeToolConfig(Transport,CodeToolsOptions);
    if Assigned(Opt) then
      Proj:=Opt.&program;
    if (Proj<>'') and FileExists(Proj) then
      begin
      DoLog('[DEBUG] Initialize.Process checkpoint 11: configuring single project');
      ConfigureSingleProject(Transport,Proj);
      end;

    // load the symbol manager if it's enabled
    DoLog('[DEBUG] Initialize.Process checkpoint 12: checking symbol settings');
    DoLog('[DEBUG]   documentSymbols=' + BoolToStr(ServerSettings.documentSymbols, true));
    DoLog('[DEBUG]   workspaceSymbols=' + BoolToStr(ServerSettings.workspaceSymbols, true));
    if ServerSettings.documentSymbols or ServerSettings.workspaceSymbols then
      begin
      DoLog('[DEBUG] Initialize.Process checkpoint 13: creating TSymbolManager');
      SymbolManager := TSymbolManager.Create;
      DoLog('[DEBUG] Initialize.Process checkpoint 14: TSymbolManager created, setting transport');
      SymbolManager.Transport := Transport;
      Result.capabilities.documentSymbolProvider:=True;
      DoLog('[DEBUG] Initialize.Process checkpoint 15: calling CanProvideWorkspaceSymbols');
      Result.capabilities.workspaceSymbolProvider := ServerSettings.CanProvideWorkspaceSymbols;
      DoLog('[DEBUG] Initialize.Process checkpoint 16: symbol manager setup done');
      end;

    // attempt to load optional config file
    DoLog('[DEBUG] Initialize.Process checkpoint 17: loading config file');
    if Assigned(Opt) then
      ConfigPath := ExpandFileName(Opt.CodeToolsConfig);
    if FileExists(ConfigPath) then
      begin
        DoLog('Loading config file: '+ ConfigPath);
        CodeToolsOptions.LoadFromFile(ConfigPath);
      end;
    // include workspace paths as search paths
    DoLog('[DEBUG] Initialize.Process checkpoint 18: collecting workspace paths');
    if ServerSettings.includeWorkspaceFoldersAsUnitPaths or
       ServerSettings.includeWorkspaceFoldersAsIncludePaths then
      begin
        CollectWorkSpacePaths(Params.workspaceFolders, Paths, ServerSettings.excludeWorkspaceFolders);
      end;
    // Add the in order specified
    Paths.Sorted:=False;
    if Assigned(Opt) then
      for Option in Opt.FPCOptions do
        begin
          // expand file names in switches with paths
          if re.Exec(Option) then
            begin
            if Paths.IndexOf(re.Match[3])=-1 then
              Paths.Add(re.Match[3])
            end;
          //else
            CodeToolsOptions.FPCOptions := CodeToolsOptions.FPCOptions + Option + ' ';
        end;

    DoLog('[DEBUG] Initialize.Process checkpoint 19: workspace symbol provider check');
    if Result.Capabilities.workspaceSymbolProvider then
      begin
      // Store workspace paths in SymbolManager for IsFileInWorkspace checks
      DoLog('[DEBUG] Initialize.Process checkpoint 20: setting up workspace paths');
      SymbolManager.WorkspacePaths.Clear;
      DoLog('[DEBUG] Initialize.Process checkpoint 20a: Paths.Count=' + IntToStr(Paths.Count));
      for aPath in Paths do
        begin
        DoLog('[DEBUG] Initialize.Process checkpoint 21a: adding to WorkspacePaths');
        SymbolManager.WorkspacePaths.Add(SymbolManager.NormalizePath(aPath));
        DoLog('[DEBUG] Initialize.Process checkpoint 21b: scanning path ' + aPath);
        SymbolManager.Scan(aPath, false);
        DoLog('[DEBUG] Initialize.Process checkpoint 21c: scan completed for ' + aPath);
        end;
      DoLog('[DEBUG] Initialize.Process checkpoint 22: workspace scanning done');
      end;

    DoLog('[DEBUG] Initialize.Process checkpoint 23: checking program setting');
    CheckProgramSetting;

    DoLog('[DEBUG] Initialize.Process checkpoint 24: showing config status');
    ShowConfigStatus(Params,Paths,CodeToolsOptions);

    DoLog('[DEBUG] Initialize.Process checkpoint 25: initializing CodeToolBoss');
    with CodeToolBoss do
      begin
        Init(CodeToolsOptions);
        IdentifierList.SortForHistory := True;
        IdentifierList.SortMethodForCompletion:=icsScopedAlphabetic;
      end;
    DoLog('[DEBUG] Initialize.Process checkpoint 26: applying settings to capabilities');
    Result.Capabilities.ApplySettings(ServerSettings);
    // Set search path for codetools.
    DoLog('[DEBUG] Initialize.Process checkpoint 27: setting up define templates');
    RootPath:=TDefineTemplate.Create('RootPath','RootPath','',CodetoolsOptions.ProjectDir,da_Directory);
    if ServerSettings.includeWorkspaceFoldersAsUnitPaths then
      begin
      UnitPathTemplate:=TDefineTemplate.Create('RootUnitPath','RootUnitPath',UnitPathMacroName, UnitPathMacro+';'+Paths.DelimitedText, da_DefineRecurse);
      RootPath.AddChild(UnitPathTemplate);
      end;
    if ServerSettings.includeWorkspaceFoldersAsIncludePaths then
      begin
      IncludePathTemplate:=TDefineTemplate.Create('RootIncludePath','RootIncludePath',IncludePathMacroName, IncludePathMacro+';'+Paths.DelimitedText, da_DefineRecurse);
      RootPath.AddChild(IncludePathTemplate);
      end;
    DoLog('[DEBUG] Initialize.Process checkpoint 28: adding to define tree');
    CodeToolBoss.DefineTree.Add(RootPath);
    DoLog('[DEBUG] Initialize.Process checkpoint 29: initialization complete');
  finally
    Paths.Free;
    re.Free;
    CodeToolsOptions.Free;
    Macros.Free;
  end;
end;





{ TInitialized }

procedure TInitialized.Process(var Params : TVoidParams);
begin
  // do nothing
end;

{ TShutdown }

function TShutdown.Process(var Params : TVoidParams): TLSPStreamable;
begin
  // do nothing
  result := nil;
end;

{ TExit }

procedure TExit.Process(var Params : TVoidParams);
begin
  Halt(0);
end;

{ TCancel }

procedure TCancel.Process(var Params : TCancelParams);
begin
  // not supported
end;



procedure TServerCapabilitiesHelper.ApplySettings(settings: TServerSettings);
begin
  if not Assigned(Settings) then
    exit;
  workspaceSymbolProvider := settings.CanProvideWorkspaceSymbols;
  workspace.workspaceFolders.supported := true;
  workspace.workspaceFolders.changeNotifications := true;

  hoverProvider := true;
  declarationProvider := true;
  definitionProvider := true;
  implementationProvider := true;
  referencesProvider := true;
  documentHighlightProvider := true;
  // finlayHintProvider:= TInlayHintOptions.Create;

  documentSymbolProvider := Assigned(SymbolManager);

  completionProvider.triggerCharacters.Add('.');
  completionProvider.triggerCharacters.Add('^');

  signatureHelpProvider.triggerCharacters.Add('(');
  signatureHelpProvider.triggerCharacters.Add(')');
  signatureHelpProvider.triggerCharacters.Add(',');

  renameProvider.prepareProvider := true;

end;

{ TLSPInitializeParams }

function TLSPInitializeParams.createInitializationOptions: TInitializationOptions;
begin
  Result:=TServerSettings.Create;
end;


end.

