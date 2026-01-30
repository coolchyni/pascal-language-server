unit PasLS.CodeToolHelper;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, FileProcs, LazUtilities,
  // Codetools
  ExprEval, DefineTemplates, CodeToolManager, CodeCache, LinkScanner, sourcelog,
  BasicCodeTools,
  // LSP
  LSP.Messages;

type
  { TCodeToolManagerHelper }

  TCodeToolManagerHelper = class helper for TCodeToolManager
  public
    procedure WriteDefinesDebugReport(Transport: TMessageTransport);
    procedure WriteUnitDirectives(Code: TCodeBuffer; Transport: TMessageTransport);
    procedure WriteUnitInfo(Code: TCodeBuffer; Transport: TMessageTransport);
  end;

implementation

{ TCodeToolManagerHelper }

procedure TCodeToolManagerHelper.WriteDefinesDebugReport(Transport: TMessageTransport);
// let the codetools calculate the defines for the directory
var
  Report: TStringList;
  
  procedure AddNodeReport(Prefix: string; DefTempl: TDefineTemplate);
  var
    s: string;
  begin
    while DefTempl <> nil do
    begin
      s := Prefix + 'Name="' + DefTempl.Name + '"';
      s := s + ' Description="' + DefTempl.Description + '"';
      s := s + ' Action="' + DefineActionNames[DefTempl.Action] + '"';
      s := s + ' Variable="' + DefTempl.Variable + '"';
      s := s + ' Value="' + dbgstr(DefTempl.Value) + '"';
      Report.Add(s);
      if DefTempl.FirstChild <> nil then
        AddNodeReport(Prefix + '    ', DefTempl.FirstChild);
      DefTempl := DefTempl.Next;
    end;
  end;

var
  Dir: string;
  Defines: TExpressionEvaluator;
  i: integer;
  LocalDefineTree: TDefineTree;
begin
  Dir := ExpandFileName(GetCurrentDir);
  LocalDefineTree := Self.DefineTree;
  
  Defines := LocalDefineTree.GetDefinesForDirectory(Dir, False);

  Report := TStringList.Create;
  try
    Report.Add('Directory: ' + Dir);
    if Defines <> nil then
    begin
      Report.Add('Defines:');
      for i := 0 to Defines.Count - 1 do
      begin
        Report.Add(Defines.Names(i) + '=' + dbgstr(Defines.Values(i)));
      end;
      Report.Add('');
    end;

    // add all nodes to report
    Report.Add('Tree:');
    AddNodeReport('  ', LocalDefineTree.RootTemplate);
  finally
    Transport.SendDiagnostic(Report.Text);
    FreeAndNil(Report);
  end;
end;

procedure TCodeToolManagerHelper.WriteUnitDirectives(Code: TCodeBuffer; Transport: TMessageTransport);
var
  Scanner: TLinkScanner;
  i: Integer;
  Dir: PLSDirective;
  FirstSortedIndex: integer;
  LastSortedIndex: integer;
  Report: TStringList;
begin
  if Code = nil then
    exit;

  // parse the unit
  if not Self.ExploreUnitDirectives(Code, Scanner) then
    raise Exception.Create('parser error');
  
  Report := TStringList.Create;
  try
    Report.Add('Scanner Debug Report:');
    Report.Add('-----------------------------------------------');
    Report.Add('CleanedSrc:');
    Report.Add(Scanner.CleanedSrc);
    Report.Add('-----------------------------------------------');
    Report.Add('Directives in compile order:');
    for i := 0 to Scanner.DirectiveCount - 1 do begin
      Dir := Scanner.Directives[i];
      Report.Add(Format('%d/%d CleanPos=%d=%s Level=%d %s "%s"',
        [i, Scanner.DirectiveCount,
         Dir^.CleanPos, Scanner.CleanedPosToStr(Dir^.CleanPos),
         Dir^.Level, dbgs(Dir^.State),
         ExtractCommentContent(Scanner.CleanedSrc, Dir^.CleanPos, Scanner.NestedComments)]));
    end;
    Report.Add('-----------------------------------------------');
    Report.Add('Directives sorted for Code and SrcPos:');
    for i := 0 to Scanner.DirectiveCount - 1 do begin
      Dir := Scanner.DirectivesSorted[i];
      Report.Add(Format('%d/%d CleanPos=%d=%s Level=%d %s "%s"',
        [i, Scanner.DirectiveCount,
         Dir^.CleanPos, Scanner.CleanedPosToStr(Dir^.CleanPos),
         Dir^.Level, dbgs(Dir^.State),
         ExtractCommentContent(Scanner.CleanedSrc, Dir^.CleanPos, Scanner.NestedComments)]));
      if Scanner.FindDirective(Code, Dir^.SrcPos, FirstSortedIndex, LastSortedIndex) then
      begin
        if FirstSortedIndex < LastSortedIndex then
          Report.Add(Format(' MULTIPLE: %d-%d', [FirstSortedIndex, LastSortedIndex]));
      end
      else
      begin
        raise Exception.Create('inconsistency: Scanner.FindDirective failed');
      end;
    end;
    Report.Add('-----------------------------------------------');
    
    Transport.SendDiagnostic(Report.Text);
  finally
    FreeAndNil(Report);
  end;
end;

procedure TCodeToolManagerHelper.WriteUnitInfo(Code: TCodeBuffer; Transport: TMessageTransport);
var
  Report: TStringList;
begin
  Report := TStringList.Create;
  try
    Report.Add('show unit info');
    Report.Add('UnitPath:');
    Report.Add(Self.GetUnitPathForDirectory(Code.Filename));

    Report.Add('IncPath:');
    Report.Add(Self.GetIncludePathForDirectory(Code.Filename));

    Report.Add('SrcPath:');
    Report.Add(Self.GetCompleteSrcPathForDirectory(Code.Filename));
    
    Transport.SendDiagnostic(Report.Text);
  finally
    FreeAndNil(Report);
  end;
end;

end.