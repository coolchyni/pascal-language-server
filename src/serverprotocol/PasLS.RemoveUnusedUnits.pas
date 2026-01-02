// Pascal Language Server
// Copyright 2025 Simon Hsu

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
unit PasLS.RemoveUnusedUnits;

{$mode objfpc}{$H+}

interface

uses
  { RTL }
  Classes, SysUtils,
  { Codetools }
  CodeToolManager, CodeCache,
  { LSP }
  LSP.Messages, LSP.Basic, LSP.Base;

Type

  { TRemoveUnusedUnits }

  TRemoveUnusedUnits = Class(TObject)
  private
    FTransport: TMessageTransport;
  Public
    Constructor Create(aTransport : TMessageTransport);
    Procedure Execute(const aDocumentURI : String; aPosition: TPosition); virtual;
    Property Transport : TMessageTransport Read FTransport;
  end;

implementation

uses
  { LSP }
  PasLS.ApplyEdit;

{ TRemoveUnusedUnits }

constructor TRemoveUnusedUnits.Create(aTransport: TMessageTransport);
begin
  FTransport:=aTransport;
end;

procedure TRemoveUnusedUnits.Execute(const aDocumentURI: String;
  aPosition: TPosition);
var
  Code: TCodeBuffer;
  Units: TStringList;
  FileName: String;
  i: Integer;
  aRange: TRange;
  RemovedCount: Integer;
begin
  // 1. Convert URI to filename and find/load the code buffer
  FileName := URIToPath(aDocumentURI);
  Code := CodeToolBoss.FindFile(FileName);
  if Code = nil then
    Code := CodeToolBoss.LoadFile(FileName, true, false);
    
  if Code = nil then
  begin
    Transport.SendDiagnostic('Cannot find or load file %s', [aDocumentURI]);
    exit;
  end;

  // 2. Find unused units using CodeToolBoss
  Units := TStringList.Create;
  try
    if not CodeToolBoss.FindUnusedUnits(Code, Units) then
    begin
      if CodeToolBoss.ErrorMessage <> '' then
        Transport.SendDiagnostic('Failed to find unused units: %s', [CodeToolBoss.ErrorMessage])
      else
        Transport.SendDiagnostic('No unused units found');
      exit;
    end;

    // 3. Remove unused units
    // Units list contains entries like "UnitName=used" or "UnitName=unused"
    RemovedCount := 0;
    for i := 0 to Units.Count - 1 do
    begin
      // Only remove units that are marked as unused (not ending with 'used')
      if not Units.ValueFromIndex[i].EndsWith('used') then
      begin
        if CodeToolBoss.RemoveUnitFromAllUsesSections(Code, Units.Names[i]) then
          Inc(RemovedCount);
      end;
    end;

    // 4. If no units were removed, notify and exit
    if RemovedCount = 0 then
    begin
      Transport.SendDiagnostic('No unused units to remove');
      exit;
    end;

    // 5. Apply the changes to the document
    aRange := TRange.Create(0, 0, MaxInt, MaxInt);
    try
      DoApplyEdit(Transport, aDocumentURI, Code.Source, aRange);
      Transport.SendDiagnostic('Removed %d unused unit(s)', [RemovedCount]);
    finally
      aRange.Free;
    end;

  finally
    Units.Free;
  end;
end;

end.

