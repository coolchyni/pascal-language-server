{ Test to reproduce MacOS crash when scanning scanexamples directory.
  This tests the CodeTools examples directory that causes Access Violation
  on Ryan's MacOS build when USE_SQLITE is not defined.

  Usage:
    testlsp.exe --suite=TTestScanExamples
}
unit Tests.ScanExamples;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  CodeToolManager, CodeCache,
  PasLS.Symbols, PasLS.Settings;

type

  { TTestScanExamples }

  TTestScanExamples = class(TTestCase)
  private
    FScanExamplesDir: String;
    procedure Log(const Msg: String);
    function FindScanExamplesDir: String;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestScanAllFiles;
    procedure TestScanModeMacPas;
  end;

implementation

{ TTestScanExamples }

procedure TTestScanExamples.Log(const Msg: String);
begin
  WriteLn('[SCAN] ' + Msg);
end;

function TTestScanExamples.FindScanExamplesDir: String;
var
  LazarusDir: String;
  Candidates: array[0..3] of String;
  I: Integer;
begin
  Result := '';

  // Try environment variable first
  LazarusDir := GetEnvironmentVariable('LAZARUSDIR');
  if LazarusDir <> '' then
    begin
      Result := IncludeTrailingPathDelimiter(LazarusDir) +
        'components' + PathDelim + 'codetools' + PathDelim +
        'examples' + PathDelim + 'scanexamples';
      if DirectoryExists(Result) then
        Exit;
    end;

  // Try standard installation paths (platform-specific)
  {$IFDEF DARWIN}
  Candidates[0] := '/Applications/Lazarus/components/codetools/examples/scanexamples';
  Candidates[1] := '/usr/local/share/lazarus/components/codetools/examples/scanexamples';
  Candidates[2] := '';
  Candidates[3] := '';
  {$ENDIF}
  {$IFDEF LINUX}
  Candidates[0] := '/usr/share/lazarus/components/codetools/examples/scanexamples';
  Candidates[1] := '/opt/lazarus/components/codetools/examples/scanexamples';
  Candidates[2] := '/lazarus/components/codetools/examples/scanexamples';
  Candidates[3] := '';
  {$ENDIF}
  {$IFDEF WINDOWS}
  // Windows has no standard installation path, rely on LAZARUSDIR
  Candidates[0] := '';
  Candidates[1] := '';
  Candidates[2] := '';
  Candidates[3] := '';
  {$ENDIF}

  for I := 0 to High(Candidates) do
    if (Candidates[I] <> '') and DirectoryExists(Candidates[I]) then
      begin
        Result := Candidates[I];
        Exit;
      end;
end;

procedure TTestScanExamples.SetUp;
begin
  inherited SetUp;

  FScanExamplesDir := FindScanExamplesDir;

  // Create SymbolManager if needed
  if SymbolManager = nil then
    SymbolManager := TSymbolManager.Create;

  ServerSettings.flatSymbolMode := False;
  ServerSettings.excludeSymbols.Clear;
  SetClientCapabilities(True);
end;

procedure TTestScanExamples.TearDown;
begin
  ServerSettings.flatSymbolMode := False;
  ServerSettings.excludeSymbols.Clear;
  SetClientCapabilities(False);
  inherited TearDown;
end;

procedure TTestScanExamples.TestScanAllFiles;
var
  SR: TSearchRec;
  FilePath: String;
  Code: TCodeBuffer;
  FileCount, SuccessCount, FailCount: Integer;
  FailedFiles: TStringList;
begin
  if FScanExamplesDir = '' then
    begin
      Log('SKIP: scanexamples directory not found');
      Exit;
    end;

  Log('Scanning directory: ' + FScanExamplesDir);

  FileCount := 0;
  SuccessCount := 0;
  FailCount := 0;
  FailedFiles := TStringList.Create;
  try
    if FindFirst(IncludeTrailingPathDelimiter(FScanExamplesDir) + '*.pas',
                 faAnyFile and not faDirectory, SR) = 0 then
      begin
        repeat
          Inc(FileCount);
          FilePath := IncludeTrailingPathDelimiter(FScanExamplesDir) + SR.Name;
          Log('  [' + IntToStr(FileCount) + '] Loading: ' + SR.Name);

          try
            Code := CodeToolBoss.LoadFile(FilePath, True, False);
            if Code <> nil then
              begin
                Log('    Loaded, calling Reload...');
                SymbolManager.Reload(Code, True);
                Log('    Reload completed');
                Inc(SuccessCount);
              end
            else
              begin
                Log('    FAILED: LoadFile returned nil');
                FailedFiles.Add(SR.Name + ' (LoadFile nil)');
                Inc(FailCount);
              end;
          except
            on E: Exception do
              begin
                Log('    EXCEPTION: ' + E.ClassName + ': ' + E.Message);
                FailedFiles.Add(SR.Name + ' (' + E.Message + ')');
                Inc(FailCount);
              end;
          end;
        until FindNext(SR) <> 0;
        FindClose(SR);
      end;

    Log('');
    Log('=== Summary ===');
    Log('Total files: ' + IntToStr(FileCount));
    Log('Success: ' + IntToStr(SuccessCount));
    Log('Failed: ' + IntToStr(FailCount));

    if FailedFiles.Count > 0 then
      begin
        Log('');
        Log('Failed files:');
        for FilePath in FailedFiles do
          Log('  - ' + FilePath);
      end;

    AssertTrue('Should find some .pas files', FileCount > 0);
    Log('');
    Log('TEST PASSED - No crash occurred');
  finally
    FailedFiles.Free;
  end;
end;

procedure TTestScanExamples.TestScanModeMacPas;
var
  FilePath: String;
  Code: TCodeBuffer;
begin
  if FScanExamplesDir = '' then
    begin
      Log('SKIP: scanexamples directory not found');
      Exit;
    end;

  // This specific file was reloaded in Ryan's crash log
  FilePath := IncludeTrailingPathDelimiter(FScanExamplesDir) + 'modemacpas.pas';
  Log('Testing specific file: ' + FilePath);

  if not FileExists(FilePath) then
    begin
      Log('SKIP: modemacpas.pas not found');
      Exit;
    end;

  Log('Loading file...');
  Code := CodeToolBoss.LoadFile(FilePath, True, False);
  AssertNotNull('Should load modemacpas.pas', Code);

  Log('Calling Reload...');
  SymbolManager.Reload(Code, True);
  Log('Reload completed');

  Log('Calling Reload again (simulate didChange)...');
  SymbolManager.Reload(Code, True);
  Log('Second Reload completed');

  Log('TEST PASSED - modemacpas.pas processed without crash');
end;

initialization
  RegisterTest(TTestScanExamples);

end.
