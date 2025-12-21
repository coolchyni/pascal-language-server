// Pascal Language Server
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
unit PasLS.Hover;

{$mode objfpc}{$H+}

interface

uses
  { Code Tools }
  CodeToolManager, CodeCache,
  { Protocol }
  LSP.BaseTypes,LSP.Base, LSP.Hover, LSP.Basic;

Type
  { THoverRequest }

  THoverRequest = class(specialize TLSPRequest<TTextDocumentPositionParams, THoverResponse>)
    function Process(var Params: TTextDocumentPositionParams): THoverResponse; override;
  end;


implementation

uses
  SysUtils, Classes, BasicCodeTools;

function ExtractPasDocComments(Code: TCodeBuffer; X, Y: Integer): String;
var
  ListOfPCodeXYPosition: TFPList;
  i: Integer;
  CodeXYPos: PCodeXYPosition;
  CommentCode: TCodeBuffer;
  CommentStart, CommentEnd: Integer;
  CommentStr, Line: String;
  Comments: TStringList;
  NestedComments: Boolean;
begin
  Result := '';
  ListOfPCodeXYPosition := nil;

  try
    if not CodeToolBoss.GetPasDocComments(Code, X, Y, ListOfPCodeXYPosition) then
      Exit;
    if (ListOfPCodeXYPosition = nil) or (ListOfPCodeXYPosition.Count = 0) then
      Exit;

    Comments := TStringList.Create;
    try
      NestedComments := CodeToolBoss.GetNestedCommentsFlagForFile(Code.Filename);

      for i := 0 to ListOfPCodeXYPosition.Count - 1 do
      begin
        CodeXYPos := PCodeXYPosition(ListOfPCodeXYPosition[i]);
        CommentCode := CodeXYPos^.Code;
        CommentCode.LineColToPosition(CodeXYPos^.Y, CodeXYPos^.X, CommentStart);

        if (CommentStart < 1) or (CommentStart > CommentCode.SourceLength) then
          Continue;

        CommentEnd := FindCommentEnd(CommentCode.Source, CommentStart, NestedComments);
        CommentStr := Copy(CommentCode.Source, CommentStart, CommentEnd - CommentStart);

        // Clean up comment markers
        CommentStr := Trim(CommentStr);
        if CommentStr = '' then
          Continue;

        // Handle // and /// style comments
        if (Length(CommentStr) >= 2) and (CommentStr[1] = '/') and (CommentStr[2] = '/') then
        begin
          // Check for /// style (PasDoc)
          if (Length(CommentStr) >= 3) and (CommentStr[3] = '/') then
            Line := Copy(CommentStr, 4, Length(CommentStr))
          else
            Line := Copy(CommentStr, 3, Length(CommentStr));
          // Remove leading space
          if (Length(Line) > 0) and (Line[1] = ' ') then
            Line := Copy(Line, 2, Length(Line));
          Comments.Add(Line);
        end
        // Handle { } style comments
        else if (Length(CommentStr) >= 2) and (CommentStr[1] = '{') then
        begin
          Line := Copy(CommentStr, 2, Length(CommentStr) - 2); // Remove { and }
          Comments.Add(Trim(Line));
        end
        // Handle (* *) style comments
        else if (Length(CommentStr) >= 4) and (CommentStr[1] = '(') and (CommentStr[2] = '*') then
        begin
          Line := Copy(CommentStr, 3, Length(CommentStr) - 4); // Remove (* and *)
          Comments.Add(Trim(Line));
        end
        else
          Comments.Add(CommentStr);
      end;

      if Comments.Count > 0 then
        Result := Comments.Text;
    finally
      Comments.Free;
    end;
  finally
    CodeToolBoss.FreeListOfPCodeXYPosition(ListOfPCodeXYPosition);
  end;
end;

function THoverRequest.Process(var Params: TTextDocumentPositionParams): THoverResponse;
var
  Code: TCodeBuffer;
  X, Y: Integer;
  Hint, DocComments: String;
  DeclCode: TCodeBuffer;
  DeclX, DeclY, NewTopLine, BlockTopLine, BlockBottomLine: Integer;
begin with Params do
  begin
    Code := CodeToolBoss.FindFile(textDocument.LocalPath);
    X := position.character;
    Y := position.line;

    try
      Hint := CodeToolBoss.FindSmartHint(Code, X + 1, Y + 1);
      // empty hint string means nothing was found
      if Hint = '' then
        exit(nil);
    except
      on E: Exception do
        begin
          LogError('Hover Error',E);
          exit(nil);
        end;
    end;

    // https://facelessuser.github.io/sublime-markdown-popups/
    // Wrap hint in markdown code
    Hint := '```pascal' + #10 + Hint + #10 + '```';

    // Try to get documentation comments
    // First find the declaration location, then get comments from there
    try
      DocComments := '';
      // Try to find declaration location first
      if CodeToolBoss.FindDeclaration(Code, X + 1, Y + 1, DeclCode, DeclX, DeclY,
                                       NewTopLine, BlockTopLine, BlockBottomLine) then
        DocComments := ExtractPasDocComments(DeclCode, DeclX, DeclY)
      else
        // If FindDeclaration fails, try current position (might be at declaration already)
        DocComments := ExtractPasDocComments(Code, X + 1, Y + 1);

      if DocComments <> '' then
        Hint := Hint + #10 + #10 + '---' + #10 + DocComments;
    except
      // Ignore errors when extracting comments
    end;

    Result := THoverResponse.Create;
    Result.contents.PlainText:=False;
    Result.contents.value:=Hint;
    Result.range.SetRange(Y, X);
  end;
end;


end.

