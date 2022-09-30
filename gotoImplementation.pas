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

unit gotoImplementation;

{$mode objfpc}{$H+}

interface

uses
  Classes, URIParser, CodeToolManager, CodeCache, BasicCodeTools,
  lsp, basic;

type
  
  { TGotoImplementation }
  
  TGotoImplementation = class(specialize TLSPRequest<TTextDocumentPositionParams, TLocation>)
    function Process(var Params: TTextDocumentPositionParams): TLocation; override;
  end;

implementation
uses
  diagnostics;
  
function TGotoImplementation.Process(var Params: TTextDocumentPositionParams): TLocation;
var
  Code: TCodeBuffer;
  NewCode: TCodeBuffer;
  X, Y: Integer;
  NewX, NewY, NewTopLine, BlockTopLine, BlockBottomLine: integer;
  RevertableJump: boolean;
begin with Params do
  begin
    Code := CodeToolBoss.FindFile(UriToFilenameEx(textDocument.uri));
    code.Revert;
    X := position.character;
    Y := position.line;

    if CodeToolBoss.JumpToMethod(Code, X + 1, Y + 1, 
      NewCode, NewX, NewY, NewTopLine, BlockTopLine, BlockBottomLine, RevertableJump) then
      begin
        Result := TLocation.Create;
        Result.URI := PathToURI(NewCode.Filename);
        Result.Range := TRange.Create(NewY - 1, NewX - 1);
      end
    else
      begin
        //PublishDiagnostic;
        Result := nil;
      end;
  end;
end;

initialization
  LSPHandlerManager.RegisterHandler('textDocument/implementation', TGotoImplementation);
end.

