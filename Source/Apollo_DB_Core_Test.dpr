program Apollo_DB_Core_Test;

{$STRONGLINKTYPES ON}
uses
  Vcl.Forms,
  System.SysUtils,
  DUnitX.Loggers.GUI.VCL,
  DUnitX.Loggers.Xml.NUnit,
  DUnitX.TestFramework,
  tstApollo_DB_Core in 'tstApollo_DB_Core.pas',
  Apollo_DB_Core in 'Apollo_DB_Core.pas',
  Apollo_Helpers in '..\Vendors\Apollo_Helpers\Source\Apollo_Helpers.pas';

begin
  Application.Initialize;
  Application.Title := 'DUnitX';
  Application.CreateForm(TGUIVCLTestRunner, GUIVCLTestRunner);
  Application.Run;
end.
