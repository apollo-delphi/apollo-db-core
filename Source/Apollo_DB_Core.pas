unit Apollo_DB_Core;

interface

uses
  Data.DB,
  FireDAC.Comp.Client,
  FireDAC.DApt,
  FireDAC.FMXUI.Wait,
  FireDAC.Stan.Async,
  FireDAC.Stan.Def,
  System.Classes;

type
  TPKey = record
    Autoincrement: Boolean;
    FieldNames: TArray<string>;
  end;

  TFieldDef = record
  public
    FieldName: string;
    NotNull: Boolean;
    OldFieldName: string;
    SQLType: string;
    procedure Init;
  end;

  TTableDef = record
    FieldDefs: TArray<TFieldDef>;
    PKey: TPKey;
    TableName: string;
  end;

  TDBConnectParams = record
    DataBase: string;
  end;

  TDBEngine = class abstract
  private
    FConnectParams: TDBConnectParams;
    FFDConnection: TFDConnection;
    function GetTableNames: TArray<string>;
    function Connected: Boolean;
  protected
    type
      TMetaDiff = (mdEqual, mdNeedToAdd, mdNeedToModify, mdNeedToDelete);
    function DifferMetadata(const aTableName: string; const aFieldDef: TFieldDef): TMetaDiff;
    procedure SetConnectParams(aConnection: TFDConnection); virtual;
  public
    function GetCreateTableSQL(const aTableDef: TTableDef): string;
    function GetModifyTableSQL(const aOldTableName: string; const aTableDef: TTableDef): TStringList; virtual;
    function TableExists(const aTableName: string): Boolean;
    procedure CloseConnection;
    procedure ExecQuery(aQuery: TFDQuery);
    procedure ExecSQL(const aSQLString: string);
    procedure OpenConnection;
    procedure OpenQuery(aQuery: TFDQuery; aFetchAll: Boolean = True);
    procedure TransactionCommit;
    procedure TransactionRollback;
    procedure TransactionStart;
    constructor Create(const aConnectParams: TDBConnectParams); reintroduce;
    destructor Destroy; override;
  end;

implementation

uses
  Apollo_Helpers,
  FireDAC.Phys.Intf,
  System.SysUtils;

{ TDBEngine }

procedure TDBEngine.CloseConnection;
begin
  FFDConnection.Connected := False;
  FFDConnection.Free;
end;

constructor TDBEngine.Create(const aConnectParams: TDBConnectParams);
begin
  FConnectParams := aConnectParams;
end;

destructor TDBEngine.Destroy;
begin
  if Connected then
    CloseConnection;

  inherited;
end;

procedure TDBEngine.ExecQuery(aQuery: TFDQuery);
begin
  aQuery.Connection := FFDConnection;
  aQuery.ExecSQL;
end;

procedure TDBEngine.ExecSQL(const aSQLString: string);
var
  dsQuery: TFDQuery;
begin
  dsQuery := TFDQuery.Create(nil);
  try
    dsQuery.SQL.Text := aSQLString;
    ExecQuery(dsQuery);
  finally
    dsQuery.Free;
  end;
end;

function TDBEngine.GetCreateTableSQL(const aTableDef: TTableDef): string;
var
  FieldDef: TFieldDef;
  i: Integer;
  sAutoincrement: string;
  sField: string;
  sFields: string;
  sNotNull: string;
begin
  i := 0;
  sFields := '';
  for FieldDef in aTableDef.FieldDefs do
  begin
    if i > 0 then
    sFields := sFields + ', ';

    if FieldDef.NotNull then
      sNotNull := ' NOT NULL'
    else
      sNotNull := '';

    sField := Format('%s %s%s', [FieldDef.FieldName, FieldDef.SQLType, sNotNull]);

    if aTableDef.PKey.FieldNames.Contains(FieldDef.FieldName) then
    begin
      if aTableDef.PKey.Autoincrement then
        sAutoincrement := ' AUTOINCREMENT'
      else
        sAutoincrement := '';

      sField := sField + Format(' PRIMARY KEY%s NOT NULL UNIQUE', [sAutoincrement]);
    end;

    sFields := sFields + sField;
    Inc(i);
  end;

  Result := Format('CREATE TABLE %s (%s);', [aTableDef.TableName, sFields]);
end;

function TDBEngine.GetModifyTableSQL(const aOldTableName: string; const aTableDef: TTableDef): TStringList;
begin
  Result := nil;
end;

function TDBEngine.GetTableNames: TArray<string>;
var
  i: Integer;
  SL: TStringList;
begin
  Result := [];
  SL := TStringList.Create;
  try
    FFDConnection.GetTableNames('', '', '', SL);

    for i := 0 to SL.Count - 1 do
      Result := Result + [SL[i]];
  finally
    SL.Free;
  end;
end;

function TDBEngine.DifferMetadata(const aTableName: string; const aFieldDef: TFieldDef): TMetaDiff;
var
  FDMetaInfoQuery: TFDMetaInfoQuery;
begin
  Result := mdEqual;

  FDMetaInfoQuery := TFDMetaInfoQuery.Create(nil);
  try
    FDMetaInfoQuery.Connection := FFDConnection;
    FDMetaInfoQuery.MetaInfoKind := mkTableFields;
    FDMetaInfoQuery.ObjectName := aTableName;
    FDMetaInfoQuery.Open;

    while not FDMetaInfoQuery.EOF do
    begin
      if FDMetaInfoQuery.FieldByName('COLUMN_NAME').AsString = aFieldDef.OldFieldName then
      begin
        if aFieldDef.OldFieldName <> aFieldDef.FieldName then
          Exit(mdNeedToModify);
      end;

      FDMetaInfoQuery.Next;
    end;
  finally
    FDMetaInfoQuery.Free;
  end;
end;

function TDBEngine.Connected: Boolean;
begin
  Result := FFDConnection.Connected;
end;

procedure TDBEngine.OpenConnection;
begin
  FFDConnection := TFDConnection.Create(nil);
  SetConnectParams(FFDConnection);

  FFDConnection.Connected := True;
end;

procedure TDBEngine.OpenQuery(aQuery: TFDQuery; aFetchAll: Boolean);
begin
  aQuery.Connection := FFDConnection;
  aQuery.Open;

  if aFetchAll then
    aQuery.FetchAll;
end;

procedure TDBEngine.SetConnectParams(aConnection: TFDConnection);
begin
  aConnection.Params.Values['Database'] := FConnectParams.DataBase;
end;

procedure TDBEngine.TransactionCommit;
begin
  FFDConnection.Commit;
end;

procedure TDBEngine.TransactionRollback;
begin
  FFDConnection.Rollback;
end;

procedure TDBEngine.TransactionStart;
begin
  FFDConnection.StartTransaction;
end;

function TDBEngine.TableExists(const aTableName: string): Boolean;
var
  TableName: string;
  TableNames: TArray<string>;
begin
  Result := False;
  TableNames := GetTableNames;

  for TableName in TableNames do
    if TableName.ToUpper = aTableName.ToUpper then
      Exit(True);
end;

{ TFieldDef }

procedure TFieldDef.Init;
begin
  FieldName := '';
  NotNull := False;
  OldFieldName := '';
  SQLType := '';
end;

end.
