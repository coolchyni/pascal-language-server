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

unit LSP.Rename;

{$mode objfpc}{$H+}

interface

uses
  { RTL }
  Classes,
  { Protocol }
  LSP.BaseTypes, LSP.Base, LSP.Basic;

type

  { TRenameParams }

  TRenameParams = class(TTextDocumentPositionParams)
  private
    fNewName: string;
  public
    procedure Assign(Source: TPersistent); override;
  published
    // The new name of the symbol. If the given name is not valid the
    // request must return a [ResponseError](#ResponseError) with an
    // appropriate message set.
    property newName: string read fNewName write fNewName;
  end;

  { TPrepareRenameParams }

  TPrepareRenameParams = class(TTextDocumentPositionParams)
  end;

  { TPrepareRenameResult }

  TPrepareRenameResult = class(TLSPStreamable)
  private
    fRange: TRange;
    fPlaceholder: string;
    procedure SetRange(AValue: TRange);
  public
    constructor Create; override;
    destructor Destroy; override;
    procedure Assign(Source: TPersistent); override;
  published
    // The range of the string to rename
    property range: TRange read fRange write SetRange;
    // A placeholder text of the string content to be renamed.
    property placeholder: string read fPlaceholder write fPlaceholder;
  end;


implementation

uses
  SysUtils;

{ TRenameParams }

procedure TRenameParams.Assign(Source: TPersistent);
var
  Src: TRenameParams absolute Source;
begin
  if Source is TRenameParams then
    begin
      inherited Assign(Source);
      newName := Src.newName;
    end
  else
    inherited Assign(Source);
end;

{ TPrepareRenameResult }

procedure TPrepareRenameResult.SetRange(AValue: TRange);
begin
  if fRange = AValue then Exit;
  fRange.Assign(AValue);
end;

constructor TPrepareRenameResult.Create;
begin
  inherited Create;
  fRange := TRange.Create;
end;

destructor TPrepareRenameResult.Destroy;
begin
  FreeAndNil(fRange);
  inherited Destroy;
end;

procedure TPrepareRenameResult.Assign(Source: TPersistent);
var
  Src: TPrepareRenameResult absolute Source;
begin
  if Source is TPrepareRenameResult then
    begin
      range.Assign(Src.range);
      placeholder := Src.placeholder;
    end
  else
    inherited Assign(Source);
end;

end.
