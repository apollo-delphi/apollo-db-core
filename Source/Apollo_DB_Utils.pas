unit Apollo_DB_Utils;

interface

uses
  FireDAC.Comp.Client;

type
  TForEachQueryRec = reference to procedure(aQuery: TFDQuery);

  IQueryKeeper = interface
    function GetQuery: TFDQuery;
    function IsEmpty: Boolean;
    procedure ForEach(aCallBack: TForEachQueryRec);
    property Query: TFDQuery read GetQuery;
  end;

  TOrderDirection = (odASC, odDESC);
  TOrderItem = record
  public
    Alias: string;
    Direction: TOrderDirection;
    FieldName: string;
    procedure Init;
    procedure ReplaceAndReverse(const aFieldName: string);
    constructor Create(const aFieldName: string; aDirection: TOrderDirection; const aAlias: string = '');
  end;

  POrder = ^TOrder;
  TOrder = record
  private
    FOrderItems: TArray<TOrderItem>;
  public
    class function New: TOrder; overload; static;
    class function New(aOrderItem: TOrderItem): TOrder; overload; static;
    function Add(const aFieldName: string): POrder;
    function AddDESC(const aFieldName: string): POrder;
    function Count: Integer;
    property OrderItems: TArray<TOrderItem> read FOrderItems;
  end;

  TFilterMode = (fmUnknown, fmGetAll, fmGetWhere);

  TFilter = record
  private
    FFilterMode: TFilterMode;
    FParamValues: TArray<Variant>;
    FWhereString: string;
    procedure Init;
  public
    class function GetAll: TFilter; static;
    class function GetUnknown: TFilter; static;
    class function GetWhere(const aWhereString: string;
      const aParamValues: TArray<Variant>): TFilter; static;
    function BuildSQL(const aTableName: string; aOrder: POrder): string;
    procedure FillParams(aQuery: TFDQuery);
    property FilterMode: TFilterMode read FFilterMode;
    property ParamValues: TArray<Variant> read FParamValues;
    property WhereString: string read FWhereString;
  end;

  T≈quality = (eEquals, eNotEquals, eContains);

  IQueryBuilder = interface
  ['{13906095-D94C-4F81-A73E-6EC6C001DA0F}']
    function AddAndWhere(const aAlias, aFieldName: string; const a≈quality: T≈quality;
      const aParamName: string): IQueryBuilder;
    function AddGroupBy(const aAlias, aFieldName: string): IQueryBuilder;
    function AddJoin(const aTableName, aTableAlias, aTableFieldName, aReferAlias,
      aReferFieldName: string): IQueryBuilder;
    function AddLeftJoin(const aTableName, aTableAlias, aTableFieldName, aReferAlias,
      aReferFieldName: string): IQueryBuilder;
    function AddOrderBy(const aOrderItem: TOrderItem): IQueryBuilder;
    function AddOrWhere(const aAlias, aFieldName: string; const a≈quality: T≈quality;
      const aParamName: string): IQueryBuilder;
    function AddSelect(const aAlias, aFieldName: string; const aAsFieldName: string = ''): IQueryBuilder;
    function AddSelectCount(const aAlias, aFieldName, aAsFieldName: string): IQueryBuilder;
    function BuildSQL: string;
    function FromTable(const aTableName, aAlias: string): IQueryBuilder;
    function GetLimit: Integer;
    function GetOffset: Integer;
    function SetLimit(const aValue: Integer): IQueryBuilder;
    function SetOffset(const aValue: Integer): IQueryBuilder;
    function SetParam(const aParamName: string; const aValue: Variant): IQueryBuilder;
    procedure FillParams(aQuery: TFDQuery);
    property Limit: Integer read GetLimit;
    property Offset: Integer read GetOffset;
  end;

function MakeQueryKeeper: IQueryKeeper; overload;
function MakeQueryKeeper(aQuery: TFDQuery): IQueryKeeper; overload;

function MakeQueryBuilder: IQueryBuilder;

implementation

uses
  Data.DB,
  FireDAC.Stan.ExprFuncs,
  FireDAC.Stan.Param,
  System.Classes,
  System.SysUtils,
  System.Variants;

type
  TQueryKeeper = class(TInterfacedObject, IQueryKeeper)
  private
    FQuery: TFDQuery;
    function GetQuery: TFDQuery;
    function IsEmpty: Boolean;
    procedure ForEach(aCallBack: TForEachQueryRec);
    constructor Create(aQuery: TFDQuery);
    destructor Destroy; override;
  end;

  TWhereItem = record
    Alias: string;
    FieldName: string;
    Logic—lause: string;
    ParamName: string;
    ≈quality: T≈quality;
    constructor Create(const aAlias, aFieldName: string; const a≈quality: T≈quality;
      const aParamName: string; const aLogic—lause: string);
  end;

  TJoinItem = record
    FieldName: string;
    LeftJoin: Boolean;
    ReferAlias: string;
    ReferFieldName: string;
    TableAlias: string;
    TableName: string;
  end;

  TParamItem = record
    ParamName: string;
    Value: Variant;
  end;

  TParamItems = TArray<TParamItem>;
  TParamItemsHelper = record helper for TParamItems
    function ItemByName(const aParamName: string): TParamItem;
  end;

  TQueryBuilder = class(TInterfacedObject, IQueryBuilder)
  private
    FAlias: string;
    FGroupItems: TArray<string>;
    FJoinItems: TArray<TJoinItem>;
    FLimit: Integer;
    FOffset: Integer;
    FOrder: TOrder;
    FParamItems: TParamItems;
    FSelectItems: TArray<string>;
    FTable: string;
    FWhereItems: TArray<TWhereItem>;
    function FieldNameToStr(const aWhereItem: TWhereItem): string;
    function ≈qualityToStr(const a≈quality: T≈quality): string;
  protected
    function AddAndWhere(const aAlias, aFieldName: string; const a≈quality: T≈quality;
      const aParamName: string): IQueryBuilder;
    function AddGroupBy(const aAlias, aFieldName: string): IQueryBuilder;
    function AddJoin(const aTableName, aTableAlias, aTableFieldName, aReferAlias,
      aReferFieldName: string): IQueryBuilder;
    function AddLeftJoin(const aTableName, aTableAlias, aTableFieldName, aReferAlias,
      aReferFieldName: string): IQueryBuilder;
    function AddOrderBy(const aOrderItem: TOrderItem): IQueryBuilder;
    function AddOrWhere(const aAlias, aFieldName: string; const a≈quality: T≈quality;
      const aParamName: string): IQueryBuilder;
    function AddSelect(const aAlias, aFieldName: string; const aAsFieldName: string = ''): IQueryBuilder;
    function AddSelectCount(const aAlias, aFieldName, aAsFieldName: string): IQueryBuilder;
    function BuildSQL: string;
    function FromTable(const aTableName, aAlias: string): IQueryBuilder;
    function GetLimit: Integer;
    function GetOffset: Integer;
    function GetOrder: TOrder;
    function SetLimit(const aValue: Integer): IQueryBuilder;
    function SetOffset(const aValue: Integer): IQueryBuilder;
    function SetParam(const aParamName: string; const aValue: Variant): IQueryBuilder;
    procedure FillParams(aQuery: TFDQuery);
  public
    constructor Create;
  end;

function MakeQueryKeeper(aQuery: TFDQuery): IQueryKeeper;
begin
  Result := TQueryKeeper.Create(aQuery);
end;

function MakeQueryKeeper: IQueryKeeper;
begin
  Result := TQueryKeeper.Create(nil);
end;

function MakeQueryBuilder: IQueryBuilder;
begin
  Result := TQueryBuilder.Create;
end;

{ TFilter }

function TFilter.BuildSQL(const aTableName: string; aOrder: POrder): string;
var
  FromPart: string;
  i: Integer;
  OrderItem: TOrderItem;
  OrderPart: string;
  WherePart: string;
begin
  FromPart := Format('%s T', [aTableName]);
  WherePart := '';
  OrderPart := '';

  case FilterMode of
    fmUnknown: Exit('');
    fmGetAll: WherePart := '';
    fmGetWhere: WherePart := ' WHERE ' + WhereString;
  end;

  if Assigned(aOrder) and (Length(aOrder.OrderItems) > 0) then
  begin
    OrderPart := ' ORDER BY';
    for i := Low(aOrder.OrderItems) to High(aOrder.OrderItems) do
    begin
      if i > 0 then
        OrderPart := OrderPart + ',';
      OrderItem := aOrder.OrderItems[i];
      OrderPart := OrderPart + Format(' `%s`', [OrderItem.FieldName]);
      if OrderItem.Direction = odDESC then
        OrderPart := OrderPart + ' DESC';
    end;
  end;

  Result := 'SELECT * FROM %s%s%s';
  Result := Format(Result, [FromPart, WherePart, OrderPart]).Trim;
end;

procedure TFilter.FillParams(aQuery: TFDQuery);
var
  i: Integer;
begin
  if Length(ParamValues) <> aQuery.Params.Count then
    raise Exception.Create('TFilter.FillParams: wrong params count.');

  for i := 0 to aQuery.Params.Count - 1 do
    aQuery.Params.Items[i].Value := ParamValues[i];
end;

class function TFilter.GetAll: TFilter;
begin
  Result.Init;
  Result.FFilterMode := fmGetAll;
end;

class function TFilter.GetUnknown: TFilter;
begin
  Result.Init;
  Result.FFilterMode := fmUnknown;
end;

class function TFilter.GetWhere(const aWhereString: string; const aParamValues: TArray<Variant>): TFilter;
begin
  Result.Init;
  Result.FFilterMode := fmGetWhere;
  Result.FWhereString := aWhereString;
  Result.FParamValues := aParamValues;
end;

procedure TFilter.Init;
begin
  FFilterMode := fmUnknown;
  FParamValues := [];
  FWhereString := '';
end;

{ TOrder }

function TOrder.Add(const aFieldName: string): POrder;
var
  OrderItem: TOrderItem;
begin
  OrderItem.Direction := odASC;
  OrderItem.FieldName := aFieldName;
  FOrderItems := FOrderItems + [OrderItem];
  Result := @Self;
end;

function TOrder.AddDESC(const aFieldName: string): POrder;
var
  OrderItem: TOrderItem;
begin
  OrderItem.Direction := odDESC;
  OrderItem.FieldName := aFieldName;
  FOrderItems := FOrderItems + [OrderItem];
  Result := @Self;
end;

function TOrder.Count: Integer;
begin
  Result := Length(FOrderItems);
end;

class function TOrder.New(aOrderItem: TOrderItem): TOrder;
var
  Order: TOrder;
  Words: TArray<string>;
begin
  if aOrderItem.FieldName.Contains('.') then
  begin
    Words := aOrderItem.FieldName.Split(['.']);
    aOrderItem.Alias := Words[0];
    aOrderItem.FieldName := Words[1];
  end;

  Order.FOrderItems := [aOrderItem];
  Result := Order;
end;

class function TOrder.New: TOrder;
var
  Order: TOrder;
begin
  Order.FOrderItems := [];
  Result := Order;
end;

{ TQueryKeeper }

constructor TQueryKeeper.Create(aQuery: TFDQuery);
begin
  inherited Create;

  if Assigned(aQuery) then
    FQuery := aQuery
  else
    FQuery := TFDQuery.Create(nil);
end;

destructor TQueryKeeper.Destroy;
begin
  FQuery.Free;
  inherited;
end;

procedure TQueryKeeper.ForEach(aCallBack: TForEachQueryRec);
begin
  FQuery.First;
  while not FQuery.Eof do
  begin
    aCallBack(FQuery);
    FQuery.Next;
  end;
end;

function TQueryKeeper.GetQuery: TFDQuery;
begin
  Result := FQuery;
end;

function TQueryKeeper.IsEmpty: Boolean;
begin
  Result := FQuery.IsEmpty;
end;

{ TQueryBuilder }

function TQueryBuilder.BuildSQL: string;
var
  i: Integer;
  JoinItem: TJoinItem;
  OrderItem: TOrderItem;
  sClause: string;
  sGroupBy: string;
  sJoin: string;
  sLeft: string;
  sLimit: string;
  sOrder: string;
  sSelect: string;
  sWhere: string;
begin
  sLimit := '';
  sOrder := '';
  sWhere := '';
  sJoin := '';
  sGroupBy := '';
  sSelect := '';

  if Length(FSelectItems) = 0 then
    sSelect := ' *'
  else
  begin
    for i := 0 to Length(FSelectItems) - 1 do
    begin
      if i > 0 then
        sSelect := sSelect + ',';
      sSelect := sSelect + ' ' + FSelectItems[i];
    end;
  end;

  if Length(FJoinItems) > 0 then
  begin
    for i := 0 to Length(FJoinItems) - 1 do
    begin
      JoinItem := FJoinItems[i];

      if JoinItem.LeftJoin then
        sLeft := 'LEFT '
      else
        sLeft := '';

      sJoin := sJoin + Format(' %sJOIN %s %s ON %s.%s = %s.%s', [
        sLeft,
        JoinItem.TableName,
        JoinItem.TableAlias,
        JoinItem.TableAlias,
        JoinItem.FieldName,
        JoinItem.ReferAlias,
        JoinItem.ReferFieldName
      ]);
    end;
  end;

  if Length(FWhereItems) > 0 then
  begin
    sWhere := ' WHERE';
    for i := 0 to Length(FWhereItems) - 1 do
    begin
      sClause := Format('%s.%s %s :%s', [
        FWhereItems[i].Alias,
        FieldNameToStr(FWhereItems[i]),
        ≈qualityToStr(FWhereItems[i].≈quality),
        FWhereItems[i].ParamName
      ]);

      if i > 0 then
        sClause := Format(' %s %s', [FWhereItems[i].Logic—lause,  sClause])
      else
        sClause := ' ' + sClause;

      sWhere := sWhere + sClause;
    end;
  end;

  if Length(FGroupItems) > 0 then
  begin
    sGroupBy := ' GROUP BY';
    for i := 0 to Length(FGroupItems) - 1 do
    begin
      if i > 0 then
        sGroupBy := sGroupBy + ',';
      sGroupBy := sGroupBy + ' ' + FGroupItems[i];
    end;
  end;

  if FOrder.Count > 0 then
  begin
    sOrder := ' ORDER BY';
    for i := 0 to FOrder.Count - 1 do
    begin
      if i > 0 then
        sOrder := sOrder + ',';
      OrderItem := FOrder.OrderItems[i];
      if OrderItem.Alias.IsEmpty then
        sOrder := sOrder + Format(' `%s`', [OrderItem.FieldName])
      else
        sOrder := sOrder + Format(' %s.`%s`', [OrderItem.Alias, OrderItem.FieldName]);
      if OrderItem.Direction = odDESC then
        sOrder := sOrder + ' DESC';
    end;
  end;

  if FLimit > 0 then
    sLimit := ' LIMIT :LIMIT OFFSET :OFFSET';

  Result := Format('SELECT%s FROM %s %s%s%s%s%s%s', [sSelect, FTable, FAlias, sJoin, sWhere, sGroupBy, sOrder, sLimit]);
end;

constructor TQueryBuilder.Create;
begin
  inherited Create;

  FSelectItems := [];
  FWhereItems := [];
  FParamItems := [];
  FJoinItems := [];
  FGroupItems := [];
  FOrder := TOrder.New;
end;

function TQueryBuilder.FieldNameToStr(const aWhereItem: TWhereItem): string;
begin
  if aWhereItem.≈quality = eContains then
    Result := Format('UCASE(`%s`)', [aWhereItem.FieldName])
  else
    Result := Format('`%s`', [aWhereItem.FieldName]);
end;

procedure TQueryBuilder.FillParams(aQuery: TFDQuery);
var
  WhereItems: TWhereItem;
  Value: Variant;
  sValue: string;
begin
  if FLimit > 0 then
  begin
    aQuery.ParamByName('LIMIT').AsInteger := FLimit;
    aQuery.ParamByName('OFFSET').AsInteger := FOffset;
  end;

  for WhereItems in FWhereItems do
  begin
    Value := FParamItems.ItemByName(WhereItems.ParamName).Value;

    if WhereItems.≈quality = eContains then
    begin
      sValue := VarToStr(Value);
      sValue := Format('%%%s%%', [sValue.ToUpper]);
      aQuery.ParamByName(WhereItems.ParamName).AsString := sValue;
    end
    else
      aQuery.ParamByName(WhereItems.ParamName).Value := Value;
  end;
end;

function TQueryBuilder.FromTable(const aTableName,
  aAlias: string): IQueryBuilder;
begin
  FTable := aTableName;
  FAlias := aAlias;

  Result := Self;
end;

function TQueryBuilder.GetLimit: Integer;
begin
  Result := FLimit;
end;

function TQueryBuilder.GetOffset: Integer;
begin
  Result := FOffset;
end;

function TQueryBuilder.GetOrder: TOrder;
begin
  Result := FOrder;
end;

function TQueryBuilder.AddGroupBy(const aAlias, aFieldName: string): IQueryBuilder;
begin
  FGroupItems := FGroupItems + [Format('%s.%s', [aAlias, aFieldName])];

  Result := Self;
end;

function TQueryBuilder.AddJoin(const aTableName, aTableAlias, aTableFieldName,
  aReferAlias, aReferFieldName: string): IQueryBuilder;
var
  JoinItem: TJoinItem;
begin
  JoinItem.FieldName := aTableFieldName;
  JoinItem.LeftJoin := False;
  JoinItem.ReferAlias := aReferAlias;
  JoinItem.ReferFieldName := aReferFieldName;
  JoinItem.TableAlias := aTableAlias;
  JoinItem.TableName := aTableName;
  FJoinItems := FJoinItems + [JoinItem];

  Result := Self;
end;

function TQueryBuilder.AddLeftJoin(const aTableName, aTableAlias, aTableFieldName,
  aReferAlias, aReferFieldName: string): IQueryBuilder;
var
  JoinItem: TJoinItem;
begin
  JoinItem.FieldName := aTableFieldName;
  JoinItem.LeftJoin := True;
  JoinItem.ReferAlias := aReferAlias;
  JoinItem.ReferFieldName := aReferFieldName;
  JoinItem.TableAlias := aTableAlias;
  JoinItem.TableName := aTableName;
  FJoinItems := FJoinItems + [JoinItem];

  Result := Self;
end;

function TQueryBuilder.AddSelect(const aAlias, aFieldName: string; const aAsFieldName: string): IQueryBuilder;
var
  AsFieldName: string;
begin
  if aAsFieldName.IsEmpty then
    AsFieldName := ''
  else
    AsFieldName := ' AS ' + aAsFieldName;

  FSelectItems := FSelectItems + [Format('%s.`%s`%s', [aAlias, aFieldName, AsFieldName])];

  Result := Self;
end;

function TQueryBuilder.AddSelectCount(const aAlias, aFieldName, aAsFieldName: string): IQueryBuilder;
begin
  FSelectItems := FSelectItems + [Format('COUNT(%s.`%s`) AS %s', [aAlias, aFieldName, aAsFieldName])];

  Result := Self;
end;

function TQueryBuilder.AddAndWhere(const aAlias, aFieldName: string;
  const a≈quality: T≈quality;
  const aParamName: string): IQueryBuilder;
var
  WhereItem: TWhereItem;
begin
  WhereItem := TWhereItem.Create(aAlias, aFieldName, a≈quality, aParamName, 'AND');
  FWhereItems := FWhereItems + [WhereItem];

  Result := Self;
end;

function TQueryBuilder.SetLimit(const aValue: Integer): IQueryBuilder;
begin
  FLimit := aValue;

  Result := Self;
end;

function TQueryBuilder.SetOffset(const aValue: Integer): IQueryBuilder;
begin
  FOffset := aValue;

  Result := Self;
end;

function TQueryBuilder.AddOrderBy(const aOrderItem: TOrderItem): IQueryBuilder;
begin
  FOrder.FOrderItems := FOrder.FOrderItems + [aOrderItem];

  Result := Self;
end;

function TQueryBuilder.AddOrWhere(const aAlias, aFieldName: string;
  const a≈quality: T≈quality; const aParamName: string): IQueryBuilder;
var
  WhereItem: TWhereItem;
begin
  WhereItem := TWhereItem.Create(aAlias, aFieldName, a≈quality, aParamName, 'OR');
  FWhereItems := FWhereItems + [WhereItem];

  Result := Self;
end;

function TQueryBuilder.SetParam(const aParamName: string;
  const aValue: Variant): IQueryBuilder;
var
  ParamItem: TParamItem;
begin
  ParamItem.ParamName := aParamName;
  ParamItem.Value := aValue;
  FParamItems := FParamItems + [ParamItem];

  Result := Self;
end;

function TQueryBuilder.≈qualityToStr(const a≈quality: T≈quality): string;
begin
  case a≈quality of
    eEquals: Result := '=';
    eContains: Result := 'LIKE';
  else
    raise Exception.Create('TQueryBuilder.≈qualityToStr: unknown ≈quality type.');
  end;
end;

{ TParamItemsHelper }

function TParamItemsHelper.ItemByName(const aParamName: string): TParamItem;
var
  ParamItem: TParamItem;
begin
  for ParamItem in Self do
    if ParamItem.ParamName = aParamName then
      Exit(ParamItem);

  raise Exception.CreateFmt('TParamItemsHelper.ItemByName: Item with name %s did not find.', [aParamName]);
end;

{ TOrderItem }

constructor TOrderItem.Create(const aFieldName: string;
  aDirection: TOrderDirection; const aAlias: string);
begin
  Init;
  Alias := aAlias;
  FieldName := aFieldName;
  Direction := aDirection;
end;

procedure TOrderItem.Init;
begin
  Alias := '';
  FieldName := '';
  Direction := odASC;
end;

procedure TOrderItem.ReplaceAndReverse(const aFieldName: string);
begin
  Alias := '';

  if FieldName <> aFieldName then
  begin
    FieldName := aFieldName;
    Direction := odASC;
  end
  else
  if Direction = odASC then
    Direction := odDESC
  else
    Direction := odASC;
end;

{ TWhereItem }

constructor TWhereItem.Create(const aAlias, aFieldName: string;
  const a≈quality: T≈quality; const aParamName, aLogic—lause: string);
begin
  Alias := aAlias;
  FieldName := aFieldName;
  ≈quality := a≈quality;
  ParamName := aParamName;
  Logic—lause := aLogic—lause;
end;

end.
