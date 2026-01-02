unit test_symbols;

// =============================================================================
// Test file for LSP DocumentSymbol breadcrumb functionality
//
// This file is used to test the breadcrumb (symbol navigation bar) feature
// in LSP client IDEs such as VS Code, when using the Pascal Language Server.
//
// Test scenarios:
// 1. Class method breadcrumb: cursor in method body should show ClassName > MethodName
// 2. Nested functions: should appear in Outline view under their parent function
// 3. Class names: should not have trailing '=' character
// 4. Global functions: should appear at root level in Outline
// =============================================================================

{$mode objfpc}{$H+}

interface

type
  { TTestClassA - Test class A }
  TTestClassA = class
  private
    FValue: Integer;
  public
    procedure MethodA1;
    procedure MethodA2;
    function MethodA3: Integer;
  end;

  { TTestClassB - Test class B }
  TTestClassB = class
  private
    FName: String;
  public
    procedure MethodB1;
    procedure MethodB2;
  end;

  { TTestRecord - Test record type }
  TTestRecord = record
    X, Y: Integer;
  end;

procedure GlobalFunction1;
function GlobalFunction2(Value: Integer): Integer;

implementation

{ TTestClassA }

procedure TTestClassA.MethodA1;
var
  LocalVar: Integer;

  // Nested procedure 1
  procedure NestedProc1;
  begin
    LocalVar := 1;
  end;

  // Nested function 2
  function NestedFunc2: Integer;

    // Deeply nested procedure
    procedure DeeplyNested;
    begin
      LocalVar := 3;
    end;

  begin
    DeeplyNested;
    Result := LocalVar;
  end;

begin
  // Test point 1: cursor here should show breadcrumb: TTestClassA > MethodA1
  NestedProc1;
  LocalVar := NestedFunc2;
end;

procedure TTestClassA.MethodA2;
begin
  // Test point 2: cursor here should show breadcrumb: TTestClassA > MethodA2
  FValue := 100;
end;

function TTestClassA.MethodA3: Integer;
begin
  // Test point 3: cursor here should show breadcrumb: TTestClassA > MethodA3
  Result := FValue;
end;

{ TTestClassB }

procedure TTestClassB.MethodB1;
begin
  // Test point 4: cursor here should show breadcrumb: TTestClassB > MethodB1
  FName := 'Test';
end;

procedure TTestClassB.MethodB2;
begin
  // Test point 5: cursor here should show breadcrumb: TTestClassB > MethodB2
  FName := FName + '!';
end;

{ Global Functions }

procedure GlobalFunction1;
var
  I: Integer;

  // Nested function inside global function
  procedure NestedInGlobal;
  begin
    I := 42;
  end;

begin
  // Test point 6: cursor here should show breadcrumb: GlobalFunction1
  NestedInGlobal;
end;

function GlobalFunction2(Value: Integer): Integer;
begin
  // Test point 7: cursor here should show breadcrumb: GlobalFunction2
  Result := Value * 2;
end;

end.
