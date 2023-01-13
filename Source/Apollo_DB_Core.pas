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

  TIndexDef = record
  public
    FieldNames: TArray<string>;
    IndexName: string;
    Unique: Boolean;
    procedure Init;
  end;

  TIndexDefsHelper = record helper for TArray<TIndexDef>
    function Contains(const aFieldNames: TArray<string>): Boolean;
  end;

  TFieldDef = record
  public
    DefaultValue: Variant;
    FieldLength: Integer; //Character and byte string column length.
    FieldName: string;
    FieldPrecision: Integer; //Numeric and date/time column precision
    FieldScale: Integer; //Numeric and date/time column scale.
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
    TableName: string;
    function GetFKeyHash: string;
    function GetIndexDef: TIndexDef;
  end;

  TFKeyDefsHelper = record helper for TArray<TFKeyDef>
    function TryGetFKeyDef(const aFieldName: string; out aFKeyDef: TFKeyDef): Boolean;
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
    Host: string;
    Password: string;
    UserName: string;
  end;

  THandleMetaDataProc = reference to procedure(aDMetaInfoQuery: TFDMetaInfoQuery);

  TDBEngine = class abstract
  private
    FFDConnection: TFDConnection;
    function GetTableNames: TArray<string>;
    function Connected: Boolean;
  protected
    FConnectParams: TDBConnectParams;
    type
      TMetaDiff = (mdEqual, mdNeedToAdd, mdNeedToModify);
    function DifferMetadata(const aTableName: string; const aFieldDef: TFieldDef): TMetaDiff; overload;
    function DifferMetadata(const aTableName: string; const aFKeyDef: TFKeyDef): TMetaDiff; overload;
    function DifferMetadata(const aTableName: string; const aIndexDef: TIndexDef): TMetaDiff; overload;
    function DifferMetadataForDrop(const aTableName: string; const aFieldDefs: TArray<TFieldDef>): TArray<string>; overload;
    function DifferMetadataForDrop(const aTableName: string; const aFKeyDefs: TArray<TFKeyDef>): TArray<string>; overload;
    function DifferMetadataForDrop(const aTableName: string; const aIndexDefs: TArray<TIndexDef>): TArray<string>; overload;
    function DoGetLastInsertedID(const aGenName: string): Integer;
    function GetAutoicrementFieldSQL: string; virtual;
    function GetAutoicrementTrigger(const aTableName, aFieldName: string): TStringList; virtual;
    function GetFieldSQLDescription(var aTableDef: TTableDef; const aFieldDef: TFieldDef): string;
    procedure ForEachMetadata(const aObjectName: string; aMetaInfoKind: TFDPhysMetaInfoKind;
      aHandleMetaDataProc: THandleMetaDataProc);
    procedure SetConnectParams(aConnection: TFDConnection); virtual;
  public
    function GetCreateTableSQL(const aTableDef: TTableDef): TStringList;
    function GetLastInsertedID(const aTableName: string): Integer; virtual;
    function GetModifyTableSQL(const aTableDef: TTableDef): TStringList; virtual;
    function GetNameQuote: string; virtual;
    function GetSQLType(const aDefaultSQLType: string): string; virtual;
    function TableExists(const aTableName: string): Boolean;
    procedure CloseConnection;
    procedure DisableForeignKeys; virtual;
    procedure EnableForeignKeys; virtual;
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
  System.SysUtils,
  System.Variants;

{ TDBEngine }

procedure TDBEngine.DisableForeignKeys;
begin
end;

procedure TDBEngine.EnableForeignKeys;
begin
end;

function TDBEngine.GetLastInsertedID(const aTableName: string): Integer;
begin
  Result := DoGetLastInsertedID('');
end;

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
  i: Integer;
  IndexDef: TIndexDef;
  sFields: string;
  slAutoicrementTrigger: TStringList;
  sPKey: string;
  sUnique: string;
  TableDef: TTableDef;
begin
  Result := TStringList.Create;
  TableDef := aTableDef;
  i := 0;
  sFields := '';

  for FieldDef in TableDef.FieldDefs do
  begin
    if i > 0 then
    sFields := sFields + ', ';

    sFields := sFields + GetFieldSQLDescription(TableDef, FieldDef);
    Inc(i);
  end;

  sPKey := '';
  if TableDef.PKey.FieldNames.Count > 1 then
    sPKey := Format(', PRIMARY KEY(%s)', [TableDef.PKey.FieldNames.CommaText]);

  Result.Add(Format('CREATE TABLE %s%s%s(%s%s);',
    [
      GetNameQuote,
      TableDef.TableName,
      GetNameQuote,
      sFields,
      sPKey
    ]
  ));

  for IndexDef in TableDef.IndexDefs do
  begin
    if IndexDef.Unique then
      sUnique := 'UNIQUE '
    else
      sUnique := '';

    Result.Add(Format('CREATE %sINDEX %s ON %s%s%s(%s);',
      [
        sUnique,
        IndexDef.IndexName,
        GetNameQuote,
        TableDef.TableName,
        GetNameQuote,
        IndexDef.FieldNames.CommaText
      ]
    ));
  end;

  if TableDef.PKey.Autoincrement then
  begin
    slAutoicrementTrigger := GetAutoicrementTrigger(TableDef.TableName, TableDef.PKey.FieldNames[0]);
    if Assigned(slAutoicrementTrigger) then
    begin
      Result.AddStrings(slAutoicrementTrigger);
      slAutoicrementTrigger.Free;
    end;
  end;
end;

function TDBEngine.GetSQLType(const aDefaultSQLType: string): string;
begin
  Result := aDefaultSQLType;
end;

function TDBEngine.GetModifyTableSQL(const aTableDef: TTableDef): TStringList;
var
  FieldDef: TFieldDef;
  aMetaDiff: TMetaDiff;
  TableDef: TTableDef;
begin
  Result := TStringList.Create;
  TableDef := aTableDef;

  for FieldDef in aTableDef.FieldDefs do
  begin
    aMetaDiff := DifferMetadata(aTableDef.OldTableName, FieldDef);

    case aMetaDiff of
      mdNeedToAdd: Result.Add(Format('ALTER TABLE %s%s%s ADD %s;',
        [
          GetNameQuote,
          TableDef.TableName,
          GetNameQuote,
          GetFieldSQLDescription(TableDef, FieldDef)
        ]
      ));
      {mdNeedToModify: Result.Add(Format('ALTER TABLE %s%s%s ALTER %s;',
        [
          GetNameQuote,
          TableDef.TableName,
          GetNameQuote,
          GetFieldSQLDescription(TableDef, FieldDef)
        ]
      ));}
    end;
  end;

///
  {for FieldDef in aTableDef.FieldDefs do
  begin
    if DifferMetadata(aTableDef.OldTableName, FieldDef) <> mdEqual then
      Exit(True);
  end;
  if Length(DifferMetadataForDrop(aTableDef.OldTableName, aTableDef.FieldDefs)) > 0 then
    Exit(True);
  for FKeyDef in aTableDef.FKeyDefs do
  begin
    if DifferMetadata(aTableDef.OldTableName, FKeyDef) <> mdEqual then
      Exit(True);
  end;
  if Length(DifferMetadataForDrop(aTableDef.OldTableName, aTableDef.FKeyDefs)) > 0 then
    Exit(True);
  for IndexDef in aTableDef.IndexDefs do
  begin
    if DifferMetadata(aTableDef.OldTableName, IndexDef) <> mdEqual then
      Exit(True);
  end;

  if Length(DifferMetadataForDrop(aTableDef.OldTableName, aTableDef.IndexDefs)) > 0 then
    Exit(True);}
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
      mkForeignKeyFields, mkIndexFields:
      begin
        FDMetaInfoQuery.ObjectName := aObjectName.Split([';'])[0];
        FDMetaInfoQuery.BaseObjectName := aObjectName.Split([';'])[1];
      end;
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
           (aDMetaInfoQuery.FieldByName('COLUMN_PRECISION').AsInteger <> aFieldDef.FieldPrecision) or
           (aDMetaInfoQuery.FieldByName('COLUMN_SCALE').AsInteger <> aFieldDef.FieldScale) or
           (aDMetaInfoQuery.FieldByName('COLUMN_LENGTH').AsInteger <> aFieldDef.FieldLength) or
           ((caAllowNull in FieldAttrs) = aFieldDef.NotNull) or
           ((caDefault in FieldAttrs) <> (aFieldDef.DefaultValue <> Null))
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

function TDBEngine.DifferMetadata(const aTableName: string; const aIndexDef: TIndexDef): TMetaDiff;
var
  IndexFieldExists: Boolean;
begin
  Result := mdNeedToModify;
  IndexFieldExists := False;

  ForEachMetadata(aTableName, mkIndexes, procedure(aDMetaInfoQuery: TFDMetaInfoQuery)
    var
      ObjectName: string;
      IsUnique: Boolean;
    begin
      ObjectName := string.Join(';', [aDMetaInfoQuery.FieldByName('INDEX_NAME').AsString, aTableName]);
      IsUnique := aDMetaInfoQuery.FieldByName('INDEX_TYPE').AsInteger = Ord(ikUnique);

      ForEachMetadata(ObjectName, mkIndexFields, procedure(aDMetaInfoQuery: TFDMetaInfoQuery)
        begin
          if (aDMetaInfoQuery.FieldByName('COLUMN_NAME').AsString = aIndexDef.FieldNames[0]) and
             (IsUnique = aIndexDef.Unique)
          then
            IndexFieldExists := True;
        end
      );
    end
  );

  if IndexFieldExists then
    Result := mdEqual;
end;

function TDBEngine.DifferMetadataForDrop(const aTableName: string; const aFieldDefs: TArray<TFieldDef>): TArray<string>;
var
  FieldsToDrop: TArray<string>;
begin
  FieldsToDrop := [];

  ForEachMetadata(aTableName, mkTableFields, procedure(aDMetaInfoQuery: TFDMetaInfoQuery)
    var
      FieldDef: TFieldDef;
      FieldInDef: Boolean;
      FieldName: string;
    begin
      FieldInDef := False;
      FieldName := aDMetaInfoQuery.FieldByName('COLUMN_NAME').AsString;
      for FieldDef in aFieldDefs do
        if FieldName = FieldDef.OldFieldName then
        begin
          FieldInDef := True;
          Break;
        end;
      if not FieldInDef then
        FieldsToDrop := FieldsToDrop + [FieldName];
    end
  );

  Result := FieldsToDrop;
end;

function TDBEngine.DifferMetadataForDrop(const aTableName: string; const aFKeyDefs: TArray<TFKeyDef>): TArray<string>;
var
  FKeysToDrop: TArray<string>;
begin
  FKeysToDrop := [];

  ForEachMetadata(aTableName, mkForeignKeys, procedure(aDMetaInfoQuery: TFDMetaInfoQuery)
    var
      FKeyName: string;
      FKTableName: string;
      ObjectName: string;
    begin
      FKTableName := aDMetaInfoQuery.FieldByName('PKEY_TABLE_NAME').AsString;
      FKeyName := aDMetaInfoQuery.FieldByName('FKEY_NAME').AsString;
      ObjectName := string.Join(';', [FKeyName, aTableName]);

      ForEachMetadata(ObjectName, mkForeignKeyFields, procedure(aDMetaInfoQuery: TFDMetaInfoQuery)
        var
          FKeyDef: TFKeyDef;
          FKeyInDef: Boolean;
        begin
          FKeyInDef := False;

          for FKeyDef in aFKeyDefs do
            if (FKeyDef.ReferenceTableName = FKTableName) and
               (FKeyDef.ReferenceFieldName = aDMetaInfoQuery.FieldByName('PKEY_COLUMN_NAME').AsString) and
               (FKeyDef.FieldName = aDMetaInfoQuery.FieldByName('COLUMN_NAME').AsString)
            then
            begin
              FKeyInDef := True;
              Break;
            end;

          if not FKeyInDef then
            FKeysToDrop := FKeysToDrop + [FKeyName];
        end
      );
    end
  );

  Result := FKeysToDrop;
end;

function TDBEngine.DifferMetadataForDrop(const aTableName: string; const aIndexDefs: TArray<TIndexDef>): TArray<string>;
var
  IndexesToDrop: TArray<string>;
begin
  IndexesToDrop := [];

  ForEachMetadata(aTableName, mkIndexes, procedure(aDMetaInfoQuery: TFDMetaInfoQuery)
    var
      ObjectName: string;
    begin
      ObjectName := string.Join(';', [aDMetaInfoQuery.FieldByName('INDEX_NAME').AsString, aTableName]);

      ForEachMetadata(ObjectName, mkIndexFields, procedure(aDMetaInfoQuery: TFDMetaInfoQuery)
        var
          IndexDef: TIndexDef;
          IndexInDef: Boolean;
        begin
          IndexInDef := False;

          for IndexDef in aIndexDefs do
            if IndexDef.FieldNames[0] = aDMetaInfoQuery.FieldByName('COLUMN_NAME').AsString then
            begin
              IndexInDef := True;
              Break;
            end;

          if not IndexInDef then
            IndexesToDrop := IndexesToDrop + [aDMetaInfoQuery.FieldByName('INDEX_NAME').AsString];
        end
      );
    end
  );

  Result := IndexesToDrop;
end;

function TDBEngine.DoGetLastInsertedID(const aGenName: string): Integer;
begin
  Result := FFDConnection.GetLastAutoGenValue(aGenName);
end;

function TDBEngine.GetAutoicrementFieldSQL: string;
begin
  Result := ' AUTOINCREMENT';
end;

function TDBEngine.GetFieldSQLDescription(var aTableDef: TTableDef; const aFieldDef: TFieldDef): string;
var
  FKeyDef: TFKeyDef;
  sDefault: string;
  sLength: string;
  sNotNull: string;
  sPKey: string;
begin
  sPKey := '';
  sLength := '';
  sNotNull := '';
  sDefault := '';

  if aTableDef.PKey.FieldNames.Contains(aFieldDef.FieldName) and (aTableDef.PKey.FieldNames.Count = 1) then
  begin
    sPKey := ' PRIMARY KEY';
    if aTableDef.PKey.Autoincrement then
      sPKey := sPKey + GetAutoicrementFieldSQL;
  end;

  if aFieldDef.FieldLength > 0 then
    sLength := Format('(%d)', [aFieldDef.FieldLength])
  else

  if aFieldDef.FieldPrecision > 0 then
    sLength := Format('(%d,%d)', [aFieldDef.FieldPrecision, aFieldDef.FieldScale]);

  if aFieldDef.NotNull then
    sNotNull := ' NOT NULL';

  if aFieldDef.DefaultValue <> Null then
    sDefault := Format(' DEFAULT ( ''%s'')', [VarToStr(aFieldDef.DefaultValue)]);

  Result := Format('%s%s%s %s%s%s%s%s',
    [
      GetNameQuote,
      aFieldDef.FieldName,
      GetNameQuote,
      GetSQLType(aFieldDef.SQLType),
      sLength,
      sPKey,
      sNotNull,
      sDefault
    ]
  );

  if aTableDef.FKeyDefs.TryGetFKeyDef(aFieldDef.FieldName, {out}FKeyDef) then
  begin
    Result := Result + Format(' REFERENCES %s%s%s("%s")',
      [
        GetNameQuote,
        FKeyDef.ReferenceTableName,
        GetNameQuote,
        FKeyDef.ReferenceFieldName
      ]
    );

    if not aTableDef.IndexDefs.Contains([FKeyDef.FieldName]) then
      aTableDef.IndexDefs := aTableDef.IndexDefs + [FKeyDef.GetIndexDef];
  end;
end;

function TDBEngine.GetAutoicrementTrigger(const aTableName, aFieldName: string): TStringList;
begin
  Result := nil;
end;

function TDBEngine.GetNameQuote: string;
begin
  Result := '"';
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
  aConnection.Params.Values['Host'] := FConnectParams.Host;
  aConnection.Params.Values['Database'] := FConnectParams.DataBase;
  aConnection.Params.Values['User_Name'] := FConnectParams.UserName;
  aConnection.Params.Values['Password'] := FConnectParams.Password;
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
  FieldPrecision := 0;
  FieldScale := 0;
  NotNull := False;
  OldFieldName := '';
  SQLType := '';
  DefaultValue := Null;
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

{ TFKeyDefsHelper }

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

{ TIndexDefsHelper }

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

{ TFKeyDef }

function TFKeyDef.GetFKeyHash: string;
begin
  Result := TStringTools.GetHash16(TableName + FieldName + ReferenceFieldName + ReferenceTableName);
end;

function TFKeyDef.GetIndexDef: TIndexDef;
begin
  Result.Init;
  Result.IndexName := 'IDX_' + GetFKeyHash;
  Result.FieldNames := [FieldName];
end;

{ TIndexDef }

procedure TIndexDef.Init;
begin
  FieldNames := [];
  IndexName := '';
  Unique := False;
end;

end.
