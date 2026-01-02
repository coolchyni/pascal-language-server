program test_program;

// =============================================================================
// Test file for LSP DocumentSymbol in program files (.lpr/.dpr)
// Program files don't have interface/implementation sections
// =============================================================================

{$mode objfpc}{$H+}

uses
  SysUtils, Classes;

type
  { TTestClass }
  TTestClass = class
  private
    FValue: Integer;
  public
    procedure TestMethod1;
    function TestMethod2: Integer;
  end;

  { TTestClass2 - Second test class }
  TTestClass2 = class
  private
    FName: String;
  public
    procedure MethodA;
    procedure MethodB;
  end;

  { TTestRecord - Test record type }
  TTestRecord = record
    X, Y: Integer;
    Name: String;
  end;

{ TTestClass }

procedure TTestClass.TestMethod1;
var
  LocalVar: Integer;

  procedure NestedProc;
  begin
    LocalVar := 1;
  end;

begin
  // Test point 1: cursor here should show breadcrumb: TTestClass > TestMethod1
  NestedProc;
end;

function TTestClass.TestMethod2: Integer;
begin
  // Test point 2: cursor here should show breadcrumb: TTestClass > TestMethod2
  Result := FValue;
end;

{ TTestClass2 }

procedure TTestClass2.MethodA;
begin
  // Test point 3: cursor here should show breadcrumb: TTestClass2 > MethodA
  FName := 'Hello';
end;

procedure TTestClass2.MethodB;
var
  Temp: Integer;

  function NestedFunc: Integer;
  begin
    Result := 42;
  end;

begin
  // Test point 4: cursor here should show breadcrumb: TTestClass2 > MethodB
  Temp := NestedFunc;
  FName := FName + IntToStr(Temp);
end;

{ Global Functions }

procedure GlobalProc;
var
  I: Integer;

  procedure NestedInGlobal;
  begin
    I := 42;
  end;

begin
  // Test point 5: cursor here should show breadcrumb: GlobalProc
  NestedInGlobal;
end;

function GlobalFunc(Value: Integer): Integer;
begin
  // Test point 6: cursor here should show breadcrumb: GlobalFunc
  Result := Value * 2;
end;

var
  TestObj: TTestClass;
  TestObj2: TTestClass2;
  TestRec: TTestRecord;

begin
  TestObj := TTestClass.Create;
  TestObj2 := TTestClass2.Create;
  try
    TestObj.TestMethod1;
    WriteLn(TestObj.TestMethod2);
    TestObj2.MethodA;
    TestObj2.MethodB;
    GlobalProc;
    WriteLn(GlobalFunc(10));
    TestRec.X := 1;
    TestRec.Y := 2;
  finally
    TestObj.Free;
    TestObj2.Free;
  end;
end.
