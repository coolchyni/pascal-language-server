unit Tests.ClientProfile;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  PasLS.ClientProfile;

type
  TTestClientProfile = class(TTestCase)
  protected
    procedure TearDown; override;
  published
    procedure TestTryStrToFeatureValidName;
    procedure TestTryStrToFeatureInvalidName;
    procedure TestFeatureToStr;
    procedure TestAllFeaturesHaveNames;
    procedure TestDefaultProfileHasNoFeatures;
    procedure TestProfileWithFeatures;
    procedure TestHasFeature;
    procedure TestSelectRegisteredProfile;
    procedure TestSelectUnknownProfileUsesDefault;
    procedure TestCurrentReturnsDefault;
    procedure TestApplyOverridesEnable;
    procedure TestApplyOverridesDisable;
    procedure TestApplyOverridesBothEnableAndDisable;
    procedure TestApplyOverridesDoesNotModifyRegistry;
    procedure TestSublimeTextHasExcludeSectionContainers;
    procedure TestSublimeTextHasExcludeInterfaceMethodDecls;
    procedure TestSublimeTextHasExcludeImplClassDefs;
  end;

implementation

procedure TTestClientProfile.TestTryStrToFeatureValidName;
var
  F: TClientFeature;
begin
  AssertTrue('flatSymbolMode should parse', TryStrToFeature('flatSymbolMode', F));
  AssertEquals('flatSymbolMode parses to cfFlatSymbolMode', Ord(cfFlatSymbolMode), Ord(F));

  AssertTrue('nullDocumentVersion should parse', TryStrToFeature('nullDocumentVersion', F));
  AssertEquals('nullDocumentVersion parses to cfNullDocumentVersion', Ord(cfNullDocumentVersion), Ord(F));

  // Case insensitive
  AssertTrue('FLATSYMBOLMODE should parse (case insensitive)', TryStrToFeature('FLATSYMBOLMODE', F));
  AssertEquals('Case insensitive parse', Ord(cfFlatSymbolMode), Ord(F));
end;

procedure TTestClientProfile.TestTryStrToFeatureInvalidName;
var
  F: TClientFeature;
begin
  AssertFalse('invalidFeature should not parse', TryStrToFeature('invalidFeature', F));
  AssertFalse('empty string should not parse', TryStrToFeature('', F));
  AssertFalse('random text should not parse', TryStrToFeature('someRandomText', F));
end;

procedure TTestClientProfile.TestFeatureToStr;
begin
  AssertEquals('cfFlatSymbolMode', 'flatSymbolMode', FeatureToStr(cfFlatSymbolMode));
  AssertEquals('cfNullDocumentVersion', 'nullDocumentVersion', FeatureToStr(cfNullDocumentVersion));
  AssertEquals('cfFilterTextOnly', 'filterTextOnly', FeatureToStr(cfFilterTextOnly));
end;

procedure TTestClientProfile.TestAllFeaturesHaveNames;
var
  F: TClientFeature;
  ParsedFeature: TClientFeature;
begin
  // Verify round-trip for all features
  for F := Low(TClientFeature) to High(TClientFeature) do
  begin
    AssertTrue('Feature ' + IntToStr(Ord(F)) + ' should have parseable name',
      TryStrToFeature(FeatureToStr(F), ParsedFeature));
    AssertEquals('Round-trip for feature ' + IntToStr(Ord(F)),
      Ord(F), Ord(ParsedFeature));
  end;
end;

procedure TTestClientProfile.TestDefaultProfileHasNoFeatures;
var
  Profile: TClientProfile;
begin
  Profile := TClientProfile.Create('TestDefault', []);
  try
    AssertEquals('Name should be TestDefault', 'TestDefault', Profile.Name);
    AssertFalse('Empty profile has no cfFlatSymbolMode', Profile.HasFeature(cfFlatSymbolMode));
    AssertFalse('Empty profile has no cfNullDocumentVersion', Profile.HasFeature(cfNullDocumentVersion));
  finally
    Profile.Free;
  end;
end;

procedure TTestClientProfile.TestProfileWithFeatures;
var
  Profile: TClientProfile;
begin
  Profile := TClientProfile.Create('TestWithFeatures', [cfFlatSymbolMode, cfNullDocumentVersion]);
  try
    AssertTrue('Profile has cfFlatSymbolMode', Profile.HasFeature(cfFlatSymbolMode));
    AssertTrue('Profile has cfNullDocumentVersion', Profile.HasFeature(cfNullDocumentVersion));
    AssertFalse('Profile does not have cfFilterTextOnly', Profile.HasFeature(cfFilterTextOnly));
  finally
    Profile.Free;
  end;
end;

procedure TTestClientProfile.TestHasFeature;
var
  Profile: TClientProfile;
  F: TClientFeature;
begin
  // Test with all features enabled
  Profile := TClientProfile.Create('AllFeatures', [cfFlatSymbolMode..cfFilterTextOnly]);
  try
    for F := Low(TClientFeature) to High(TClientFeature) do
      AssertTrue('All features should be present', Profile.HasFeature(F));
  finally
    Profile.Free;
  end;
end;

procedure TTestClientProfile.TearDown;
begin
  TClientProfile.SelectProfile('');
end;

procedure TTestClientProfile.TestSelectRegisteredProfile;
begin
  // Sublime Text LSP is registered in initialization
  TClientProfile.SelectProfile('Sublime Text LSP');
  AssertEquals('Selected Sublime Text profile', 'Sublime Text LSP', TClientProfile.Current.Name);
  AssertTrue('Sublime has cfFlatSymbolMode', TClientProfile.Current.HasFeature(cfFlatSymbolMode));
end;

procedure TTestClientProfile.TestSelectUnknownProfileUsesDefault;
begin
  TClientProfile.SelectProfile('UnknownClient');
  AssertEquals('Unknown client uses Default', 'Default', TClientProfile.Current.Name);
  AssertFalse('Default has no cfFlatSymbolMode', TClientProfile.Current.HasFeature(cfFlatSymbolMode));
end;

procedure TTestClientProfile.TestCurrentReturnsDefault;
begin
  // Reset by selecting empty string
  TClientProfile.SelectProfile('');
  AssertNotNull('Current should not be nil', TClientProfile.Current);
  AssertEquals('Current should be Default', 'Default', TClientProfile.Current.Name);
end;

procedure TTestClientProfile.TestApplyOverridesEnable;
var
  EnableList: TStringList;
begin
  TClientProfile.SelectProfile('vscode');
  AssertFalse('VSCode has no cfFlatSymbolMode by default',
    TClientProfile.Current.HasFeature(cfFlatSymbolMode));

  EnableList := TStringList.Create;
  try
    EnableList.Add('flatSymbolMode');
    TClientProfile.ApplyOverrides(EnableList, nil);
    AssertTrue('VSCode now has cfFlatSymbolMode after override',
      TClientProfile.Current.HasFeature(cfFlatSymbolMode));
  finally
    EnableList.Free;
  end;
end;

procedure TTestClientProfile.TestApplyOverridesDisable;
var
  DisableList: TStringList;
begin
  TClientProfile.SelectProfile('Sublime Text LSP');
  AssertTrue('Sublime has cfFlatSymbolMode by default',
    TClientProfile.Current.HasFeature(cfFlatSymbolMode));

  DisableList := TStringList.Create;
  try
    DisableList.Add('flatSymbolMode');
    TClientProfile.ApplyOverrides(nil, DisableList);
    AssertFalse('Sublime no longer has cfFlatSymbolMode after override',
      TClientProfile.Current.HasFeature(cfFlatSymbolMode));
  finally
    DisableList.Free;
  end;
end;

procedure TTestClientProfile.TestApplyOverridesBothEnableAndDisable;
var
  EnableList, DisableList: TStringList;
begin
  TClientProfile.SelectProfile('vscode');

  EnableList := TStringList.Create;
  DisableList := TStringList.Create;
  try
    EnableList.Add('flatSymbolMode');
    EnableList.Add('nullDocumentVersion');
    DisableList.Add('flatSymbolMode'); // Disable takes precedence

    TClientProfile.ApplyOverrides(EnableList, DisableList);

    AssertFalse('Disable takes precedence over enable',
      TClientProfile.Current.HasFeature(cfFlatSymbolMode));
    AssertTrue('nullDocumentVersion should be enabled',
      TClientProfile.Current.HasFeature(cfNullDocumentVersion));
  finally
    EnableList.Free;
    DisableList.Free;
  end;
end;

procedure TTestClientProfile.TestApplyOverridesDoesNotModifyRegistry;
var
  EnableList: TStringList;
begin
  // First apply override
  TClientProfile.SelectProfile('vscode');
  EnableList := TStringList.Create;
  try
    EnableList.Add('flatSymbolMode');
    TClientProfile.ApplyOverrides(EnableList, nil);
  finally
    EnableList.Free;
  end;

  // Re-select the same profile - should get original features
  TClientProfile.SelectProfile('vscode');
  AssertFalse('Re-selected profile should have original features',
    TClientProfile.Current.HasFeature(cfFlatSymbolMode));
end;

procedure TTestClientProfile.TestSublimeTextHasExcludeSectionContainers;
begin
  TClientProfile.SelectProfile('Sublime Text LSP');
  AssertTrue('Sublime has cfExcludeSectionContainers',
    TClientProfile.Current.HasFeature(cfExcludeSectionContainers));
end;

procedure TTestClientProfile.TestSublimeTextHasExcludeInterfaceMethodDecls;
begin
  TClientProfile.SelectProfile('Sublime Text LSP');
  AssertTrue('Sublime has cfExcludeInterfaceMethodDecls',
    TClientProfile.Current.HasFeature(cfExcludeInterfaceMethodDecls));
end;

procedure TTestClientProfile.TestSublimeTextHasExcludeImplClassDefs;
begin
  TClientProfile.SelectProfile('Sublime Text LSP');
  AssertTrue('Sublime has cfExcludeImplClassDefs',
    TClientProfile.Current.HasFeature(cfExcludeImplClassDefs));
end;

initialization
  RegisterTest(TTestClientProfile);

end.
