unit Apollo_DB_Core;

interface

uses
  Data.DB,
  FireDAC.Comp.Client,
  FireDAC.DApt,
  FireDAC.Phys.Intf,
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
    FieldLength: Integer;
    NotNull: Boolean;
    OldFieldName: string;
    SQLType: string;
    procedure Init;
  end;

  TFKeyDef = record
  public
    FieldName: string;
    ReferenceFieldName: string;
    ReferenceTableName: string;
    function GetFKeyHash: string;
  end;

  TFKeyDefsHelper = record helper for TArray<TFKeyDef>
    function TryGetFKeyDef(const aFieldName: string; out aFKeyDef: TFKeyDef): Boolean;
  end;

  TIndexDef = record
    FieldNames: TArray<string>;
    IndexName: string;
  end;

  TIndexDefsHelper = record helper for TArray<TIndexDef>
    function Contains(const aFieldNames: TArray<string>): Boolean;
  end;

  TTableDef = record
  public
    FieldDefs: TArray<TFieldDef>;
    FKeyDefs: TArray<TFKeyDef>;
    IndexDefs: TArray<TIndexDef>;
    OldTableName: string;
    PKey: TPKey;
    TableName: string;
    procedure Init;
  end;

  TDBConnectParams = record
    DataBase: string;
  end;

  THandleMetaDataProc = reference to procedure(aDMetaInfoQuery: TFDMetaInfoQuery);

  TDBEngine = class abstract
  private
    FConnectParams: TDBConnectParams;
    FFDConnection: TFDConnection;
    function GetTableNames: TArray<string>;
    function Connected: Boolean;
  protected
    type
      TMetaDiff = (mdEqual, mdNeedToAdd, mdNeedToModify);
    function DifferMetadata(const aTableName: string; const aFieldDef: TFieldDef): TMetaDiff; overload;
    function DifferMetadata(const aTableName: string; const aFKeyDef: TFKeyDef): TMetaDiff; overload;
    procedure ForEachMetadata(const aObjectName: string; aMetaInfoKind: TFDPhysMetaInfoKind;
      aHandleMetaDataProc: THandleMetaDataProc);
    procedure SetConnectParams(aConnection: TFDConnection); virtual;
  public
    function GetCreateTableSQL(const aTableDef: TTableDef): TStringList;
    function GetModifyTableSQL(const aTableDef: TTableDef): TStringList; virtual;
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
  FireDAC.Stan.Intf,
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

function TDBEngine.GetCreateTableSQL(const aTableDef: TTableDef): TStringList;
var
  FieldDef: TFieldDef;
  FKeyDef: TFKeyDef;
  i: Integer;
  IndexDef: TIndexDef;
  sField: string;
  sFields: string;
  sLength: string;
  sNotNull: string;
  sPKey: string;
  TableDef: TTableDef;
begin
  Result := TStringList.Create;
  TableDef := aTableDef;
  i := 0;
  sFields := '';

  for FieldDef in TableDef.FieldDefs do
  begin
    sPKey := '';
    sLength := '';
    sNotNull := '';

    if i > 0 then
    sFields := sFields + ', ';

    if TableDef.PKey.FieldNames.Contains(FieldDef.FieldName) and (TableDef.PKey.FieldNames.Count = 1) then
    begin
      sPKey := ' PRIMARY KEY';
      if TableDef.PKey.Autoincrement then
        sPKey := sPKey +' AUTOINCREMENT';
    end;

    if FieldDef.FieldLength > 0 then
      sLength := Format('(%d)', [FieldDef.FieldLength]);

    if FieldDef.NotNull then
      sNotNull := ' NOT NULL';

    sField := Format('`%s` %s%s%s%s', [FieldDef.FieldName, FieldDef.SQLType, sLength, sPKey, sNotNull]);

    if TableDef.FKeyDefs.TryGetFKeyDef(FieldDef.FieldName, FKeyDef) then
    begin
      sField := sField + Format(' REFERENCES %s(%s)', [FKeyDef.ReferenceTableName, FKeyDef.ReferenceFieldName]);

      if not TableDef.IndexDefs.Contains([FKeyDef.FieldName]) then
      begin
        IndexDef.IndexName := 'IDX_' + FKeyDef.GetFKeyHash;
        IndexDef.FieldNames := [FKeyDef.FieldName];
        TableDef.IndexDefs := TableDef.IndexDefs + [IndexDef];
      end;
    end;

    sFields := sFields + sField;
    Inc(i);
  end;

  sPKey := '';
  if TableDef.PKey.FieldNames.Count > 1 then
    sPKey := Format(', PRIMARY KEY(%s)', [TableDef.PKey.FieldNames.CommaText]);

  Result.Add(Format('CREATE TABLE %s (%s%s);', [TableDef.TableName, sFields, sPKey]));

  for IndexDef in TableDef.IndexDefs do
    Result.Add(Format('CREATE INDEX %s ON %s(%s);', [IndexDef.IndexName, TableDef.TableName, IndexDef.FieldNames.CommaText]));
end;

function TDBEngine.GetModifyTableSQL(const aTableDef: TTableDef): TStringList;
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

procedure TDBEngine.ForEachMetadata(const aObjectName: string; aMetaInfoKind: TFDPhysMetaInfoKind;
  aHandleMetaDataProc: THandleMetaDataProc);
var
  FDMetaInfoQuery: TFDMetaInfoQuery;
begin
  FDMetaInfoQuery := TFDMetaInfoQuery.Create(nil);
  try
    FDMetaInfoQuery.Connection := FFDConnection;
    FDMetaInfoQuery.MetaInfoKind := aMetaInfoKind;
    case aMetaInfoKind of
      mkForeignKeyFields:
      begin
        FDMetaInfoQuery.ObjectName := aObjectName.Split([';'])[0];
        FDMetaInfoQuery.BaseObjectName := aObjectName.Split([';'])[1];
      end
    else
      FDMetaInfoQuery.ObjectName := aObjectName;
    end;
    FDMetaInfoQuery.Open;

    while not FDMetaInfoQuery.EOF do
    begin
      aHandleMetaDataProc(FDMetaInfoQuery);
      FDMetaInfoQuery.Next;
    end;
  finally
    FDMetaInfoQuery.Free;
  end;
end;

function TDBEngine.DifferMetadata(const aTableName: string; const aFieldDef: TFieldDef): TMetaDiff;
var
  FieldAttrs: TFDDataAttributes;
  FieldExists: Boolean;
  i: Integer;
  MetaDiff: TMetaDiff;
begin
  MetaDiff := mdEqual;

  FieldExists := False;

  ForEachMetadata(aTableName, mkTableFields, procedure(aDMetaInfoQuery: TFDMetaInfoQuery)
    begin
      i := aDMetaInfoQuery.FieldByName('COLUMN_ATTRIBUTES').AsInteger;
      FieldAttrs := TFDDataAttributes(Pointer(@i)^);

      if aDMetaInfoQuery.FieldByName('COLUMN_NAME').AsString = aFieldDef.OldFieldName then
      begin
        if (aFieldDef.OldFieldName <> aFieldDef.FieldName) or
           (aDMetaInfoQuery.FieldByName('COLUMN_TYPENAME').AsString <> aFieldDef.SQLType) or
           (aDMetaInfoQuery.FieldByName('COLUMN_LENGTH').AsInteger <> aFieldDef.FieldLength) or
           ((caAllowNull in FieldAttrs) = aFieldDef.NotNull)
        then
          MetaDiff := mdNeedToModify;
      end;

      if aDMetaInfoQuery.FieldByName('COLUMN_NAME').AsString = aFieldDef.FieldName then
        FieldExists := True;
    end
  );

  if MetaDiff <> mdEqual then
    Exit(MetaDiff);


  if not FieldExists then
    Exit(mdNeedToAdd);

  Result := MetaDiff;
end;

function TDBEngine.DifferMetadata(const aTableName: string; const aFKeyDef: TFKeyDef): TMetaDiff;
var
  FKFieldNameExists: Boolean;
  FKRefFieldExists: Boolean;
  FKRefTableExists: Boolean;
  MetaDiff: TMetaDiff;
begin
  MetaDiff := mdNeedToModify;
  FKRefTableExists := False;

  ForEachMetadata(aTableName, mkForeignKeys, procedure(aDMetaInfoQuery: TFDMetaInfoQuery)
    var
      ObjectName: string;
    begin
      FKRefFieldExists := False;
      FKFieldNameExists := False;

      if aDMetaInfoQuery.FieldByName('PKEY_TABLE_NAME').AsString  = aFKeyDef.ReferenceTableName then
      begin
        FKRefTableExists := True;
        ObjectName := string.Join(';', [aDMetaInfoQuery.FieldByName('FKEY_NAME').AsString, aTableName]);

        ForEachMetadata(ObjectName, mkForeignKeyFields, procedure(aDMetaInfoQuery: TFDMetaInfoQuery)
          begin
            if aDMetaInfoQuery.FieldByName('PKEY_COLUMN_NAME').AsString  = aFKeyDef.ReferenceFieldName then
              FKRefFieldExists := True;

            if aDMetaInfoQuery.FieldByName('COLUMN_NAME').AsString  = aFKeyDef.FieldName then
              FKFieldNameExists := True;
          end
        );
      end;

      if FKRefTableExists and FKRefFieldExists and FKFieldNameExists then
        MetaDiff := mdEqual;
    end
  );

  Result := MetaDiff;
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
  FieldLength := 0;
  NotNull := False;
  OldFieldName := '';
  SQLType := '';
end;

{ TTableDef }

procedure TTableDef.Init;
begin
  FieldDefs := [];
  FKeyDefs := [];
  IndexDefs := [];
  OldTableName := '';
  PKey.Autoincrement := False;
  PKey.FieldNames := [];
  TableName := '';
end;

{TFKeyDefsHelper}

function TFKeyDefsHelper.TryGetFKeyDef(const aFieldName: string; out aFKeyDef: TFKeyDef): Boolean;
var
  FKeyDef: TFKeyDef;
begin
  Result := False;

  for FKeyDef in Self do
    if FKeyDef.FieldName = aFieldName then
    begin
      aFKeyDef := FKeyDef;
      Exit(True);
    end;
end;

{TIndexDefsHelper}

function TIndexDefsHelper.Contains(const aFieldNames: TArray<string>): Boolean;
var
  FieldName: string;
  FieldNamesTheSame: Boolean;
  IndexDef: TIndexDef;
begin
  Result := False;

  for IndexDef in Self do
    if (IndexDef.FieldNames.Count = aFieldNames.Count) then
    begin
      FieldNamesTheSame := True;
      for FieldName in aFieldNames do
        if not IndexDef.FieldNames.Contains(FieldName) then
        begin
          FieldNamesTheSame := False;
          Break;
        end;

      if FieldNamesTheSame then
        Exit(True);
    end;
end;

{TFKeyDef}

function TFKeyDef.GetFKeyHash: string;
begin
  Result := TStringTools.GetHash16(FieldName + ReferenceFieldName + ReferenceTableName);
end;

end.
