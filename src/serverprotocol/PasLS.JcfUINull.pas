// Pascal Language Server
// Copyright 2026 Simon Hsu

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

unit PasLS.JcfUINull;
{$mode ObjFPC}
interface

uses
  System.UITypes, ParseTreeNode,JcfUiTools; 

type
  TJcfUINull = class(TJcfUIBase)
  public
    procedure UpdateGUI(aCounter: integer = 0; aUpdateInterval: integer = 512); override;
    function MessageDlgUI(const aMessage: string): TModalResult; override;
    procedure ShowErrorMessageUI(const aMessage: string); override;
    procedure SetWaitCursorUI; override;
    procedure RestoreCursorUI; override;
    procedure ShowParseTreeUI(const pcRoot: TParseTreeNode); override;
    function OpenDocumentUI(const aPath: string): boolean; override;
  end;

implementation

procedure TJcfUINull.UpdateGUI(aCounter: integer; aUpdateInterval: integer);
begin

end;

function TJcfUINull.MessageDlgUI(const aMessage: string): TModalResult;
begin
  /// The Language Server Protocol (LSP) must remain non-blocking.
  /// When user confirmation or a dialog interaction is required, 
  /// it defaults to "OK" or "Yes" to ensure continuous execution.
  Result := mrOK;
end;

procedure TJcfUINull.ShowErrorMessageUI(const aMessage: string);
begin

end;

procedure TJcfUINull.SetWaitCursorUI;
begin
  // ignore
end;

procedure TJcfUINull.RestoreCursorUI;
begin
  // ignore
end;

procedure TJcfUINull.ShowParseTreeUI(const pcRoot: TParseTreeNode);
begin
  // ignore
end;

function TJcfUINull.OpenDocumentUI(const aPath: string): boolean;
begin
  // LSP should not open documents in an editor.
  Result := True;
end;

end.
