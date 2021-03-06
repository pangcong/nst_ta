/* 
 * Nerr Smart Trader - Triangular Arbitrage Trading System -> Swap
 *
 * By Leon Zhuang
 * Twitter @Nerrsoft
 * leon@nerrsoft.com
 * http://nerrsoft.com
 * 
 */

#property copyright "Copyright ? 2013 Nerrsoft.com"
#property link      "http://nerrsoft.com"
#property indicator_chart_window



/* 
 * include library
 *
 */

#include <nst_lib_all.mqh>
#include <postgremql4.mqh>



/* 
 * define input parameter
 *
 */

extern int    MagicNumber              = 701;
extern string LogPriceAccountSettings  = "---Log Price & Account Info Settings---";
extern bool   LogPriceData             = true;
extern double FpiTrigger               = 0.9997;
extern bool   PlaySoundWhenTrigger     = true;
extern string LogMarginDataSettings    = "---Log Margin Data Settings---";
extern bool   LogMarginData            = false;
extern string DatabaseSettings         = "---PostgreSQL Database Settings---";
extern string g_db_ip_setting          = "localhost";
extern string g_db_port_setting        = "5432";
extern string g_db_user_setting        = "postgres";
extern string g_db_password_setting    = "911911";
extern string g_db_name_setting        = "nst";



/* 
 * Global variable
 *
 */

string Ring[2, 3], SymExt;
string SymbolArr[5] = {"USDJPY", "USDMXN", "MXNJPY", "EURJPY", "EURMXN"};
double FPI[2, 7];
bool nottradesingal = false;
int RingNum = 2;
int RingSpread[2];
int orderTableX[6] = {25, 100, 200, 300, 400, 500};

//-- insert margin data to db var
double test_swap, test_commission, test_pl;
datetime tm;
int std_t = 0;
int orderLine = 0;

//-- log price info
int account, aid;
bool logstatus;
double avgfpi;



/* 
 * System Funcs
 *
 */

//-- init
int init()
{
    //-- begin script and connect to pgsql
    string res = pmql_connect(g_db_ip_setting, g_db_port_setting, g_db_user_setting, g_db_password_setting, g_db_name_setting);
    if((res != "ok") && (res != "already connected"))
    {
        libDebugOutputLog("DB not connected!", "PGSQL-ERR");
        return (-1);
    }

    Ring[0][0] = "USDJPY"; Ring[0][1] = "USDMXN"; Ring[0][2] = "MXNJPY";
    Ring[1][0] = "EURJPY"; Ring[1][1] = "EURMXN"; Ring[1][2] = "MXNJPY";

    if(StringLen(Symbol()) > 6)
        SymExt = StringSubstr(Symbol(),6);

    //-- initDebugInfo
    initDebugInfo(Ring);

    return(0);
}

//-- deinit
int deinit()
{
    pmql_disconnect();
    return(0);
}

//-- start
int start()
{
    //-- get account id
    account = AccountNumber();
    aid = getAccountIdByAccountNum(account);

    getFPI(FPI, Ring);

    avgfpi = FPI[0][2]+FPI[1][2];
    if(avgfpi > 0)
    {
        if((avgfpi/2) >= FpiTrigger)
        {
            if(LogPriceData == true)
                logPriceInfo2Db();

            if(PlaySoundWhenTrigger == true)
                PlaySound("alert2.wav");
        }
    }

    if(LogMarginData == true)
        logSafeMarginTest2Db();

    updateFpiInfo(FPI);
    updateAccountInfo();
    updateSwapInfo(Ring);
    updateOrderInfo(MagicNumber);
    updateLogStatusInfo(aid);

    return(0);
}


//-- init debug info object on chart
void initDebugInfo(string _ring[][])
{
    ObjectsDeleteAll();

    color titlecolor = C'0xd9,0x26,0x59';
    int y, i, j;
    int ringnum = ArrayRange(_ring, 0);

    //-- set background
    libVisualCreateTextObj("_background", 15, 15, "g", C'0x27,0x28,0x22', "Webdings", 800);

    //-- set fpi table
    y += 15;
    libVisualCreateTextObj("fpi_header", 25,    y, ">>> Rings(" + ringnum + ") & FPI", titlecolor);
    y += 15;
    string fpiTableHeaderName[12] = {"Id", "SymbolA", "SymbolB", "SymbolC", "lFPI", "lLowest", "sFPI", "sHighest", "lThold", "sThold", "Spread", "MinSpread"};
    int    fpiTableHeaderX[12]    = {25, 50, 115, 181, 250, 325, 400, 475, 550, 625, 700, 775};
    for(i = 0; i < 12; i++)
        libVisualCreateTextObj("fpi_header_col_" + i, fpiTableHeaderX[i], y, fpiTableHeaderName[i]);

    for(i = 0; i < ringnum; i ++)
    {
        y += 15;

        for (j = 0; j < 12; j ++) 
        {
            if(j == 0) 
                libVisualCreateTextObj("fpi_body_row_" + (i) + "_col_" + (j), fpiTableHeaderX[j], y, (i+1), Gray);
            else if(j > 0 & j < 4) 
                libVisualCreateTextObj("fpi_body_row_" + (i) + "_col_" + (j), fpiTableHeaderX[j], y, _ring[i][j-1], White);
            else 
                libVisualCreateTextObj("fpi_body_row_" + (i) + "_col_" + (j), fpiTableHeaderX[j], y);
        }
    }

    //-- set swap table
    y += 15 * 2;
    libVisualCreateTextObj("swap_header", 25, y, ">>> Swap Estimate (1 Lots) [SR/ODS]", titlecolor);
    int swapTableHeaderX[5] = {25, 50, 200, 350, 500};
    int swapTableValueX[7] = {50, 100, 200, 250, 350, 400, 500};
    for(i = 0; i < ringnum; i ++)
    {
        y += 15;
        libVisualCreateTextObj("swap_header_row_" + i + "_col_0", swapTableHeaderX[0], y, (i+1), Gray);
        for(j = 0; j < 3; j++)
            libVisualCreateTextObj("swap_header_row_" + i + "_col_" + (j+1), swapTableHeaderX[j+1], y, _ring[i][j]);
        libVisualCreateTextObj("swap_header_row_" + i + "_col_4", swapTableHeaderX[4], y, "Total");

        y += 15;
        for(j = 0; j < 7; j++)
            libVisualCreateTextObj("swap_value_row_" + i + "_col_" + j, swapTableValueX[j], y, "", White);
    }

    //-- set account table
    y += 15 * 2;
    libVisualCreateTextObj("account_header", 25, y, ">>> Account Info", titlecolor);
    string accountTableName[5] = {"Balance", "Profit/Loss", "Equity", "Used Margin", "Free Margin"};
    int accountTableX[5] = {25, 100, 200, 300, 400};
    y += 15;
    for(i = 0; i < 5; i++)
    {
        libVisualCreateTextObj("account_header_col_" + i, accountTableX[i], y, accountTableName[i]);
        libVisualCreateTextObj("account_value_col_" + i, accountTableX[i], (y + 15), "", White);
    }

    //-- set order table
    y += 15 * 3;
    libVisualCreateTextObj("order_header", 25, y, ">>> Order Summary", titlecolor);
    string orderTableName[6] = {"Symbol", "Size(Lot)", "Profit/Loss", "Commission", "Swap", "Total"};
    
    y += 15;
    for(i = 0; i < 6; i++)
    {
        libVisualCreateTextObj("order_header_col_" + i, orderTableX[i], y, orderTableName[i]);
    }
    orderLine = y;

    //-- set log price and account info table
    libVisualCreateTextObj("log_price_data", 500, 180, ">>> Log Status", titlecolor);
    libVisualCreateTextObj("log_price_data_date", 500, 195, libDatetimeGetDate(TimeLocal()), GreenYellow);
    libVisualCreateTextObj("log_price_data_status", 500, 210, "No log", White);
}

void updateOrderInfo(int _mn)
{
    string prefix = "order_body_row_";
    int j, i, y = orderLine;
    double oinfo[5][5]; //--size; profit; commission; swap; total;
    double sum[5];

    for(i = 0; i < 6; i ++)
    {
        for(j = 0; j < 6; j ++)
        {
            if(ObjectType(prefix + i + "_col_" + j) > 0)
                ObjectDelete(prefix + i + "_col_" + j);

            oinfo[i][j] = 0;
        }

        if(ObjectType("order_summary_col_" + i) > 0)
            ObjectDelete("order_summary_col_" + i);
    }

    int idx;
    for(i = 0; i < OrdersTotal(); i++)
    {
        if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
            if(OrderMagicNumber() == _mn)
            {
                idx = checkSymbolIdx(OrderSymbol());
                oinfo[idx][4] = 0;

                oinfo[idx][0] += OrderLots();
                oinfo[idx][1] += OrderProfit();
                oinfo[idx][2] += OrderCommission();
                oinfo[idx][3] += OrderSwap();

                oinfo[idx][4] += oinfo[idx][1] + oinfo[idx][2] + oinfo[idx][3];


                test_pl += OrderProfit();
                test_commission += OrderCommission();
                test_swap += OrderSwap();
            }
        }
    }
    
    for(i = 0; i < 6; i ++)
    {
        if(oinfo[i][0] > 0)
        {
            y += 15;
            libVisualCreateTextObj(prefix + i + "_col_0", orderTableX[0], y, SymbolArr[i], White);
            for(j = 1; j < 6; j ++)
            {
                libVisualCreateTextObj(prefix + i + "_col_" + j, orderTableX[j], y, DoubleToStr(oinfo[i][j-1], 2), White);
                sum[j-1] += oinfo[i][j-1];
            }
        }
    }

    if(y > 255)
    {
        y += 15;
        libVisualCreateTextObj("order_summary_col_0", 25, y, "Summary", C'0xd9,0x26,0x59');

        for(i = 0; i < 5; i++)
        {
            if(sum[i] > 0)
                libVisualCreateTextObj("order_summary_col_"+(i+1), orderTableX[i+1],y, DoubleToStr(sum[i], 2), DeepSkyBlue);
            else
                libVisualCreateTextObj("order_summary_col_"+(i+1), orderTableX[i+1],y, DoubleToStr(sum[i], 2), LightSeaGreen);
        }
    }

    ArrayInitialize(sum, 0);
}

int checkSymbolIdx(string _sym)
{
    for(int i = 0; i < 6; i ++)
    {
        if(_sym == SymbolArr[i])
            return(i);
    }
    return(10);
}

void updateSwapInfo(string &_ring[][3])
{
    double sinfo[7];

    for(int i = 0; i < ArrayRange(_ring, 0); i++)
    {
        sinfo[0] = MarketInfo(_ring[i][0], MODE_SWAPLONG);
        sinfo[2] = MarketInfo(_ring[i][1], MODE_SWAPSHORT);
        sinfo[4] = MarketInfo(_ring[i][2], MODE_SWAPSHORT);
        
        sinfo[1] = sinfo[0];
        sinfo[3] = sinfo[2] / MarketInfo(_ring[i][1], MODE_ASK);
        sinfo[5] = sinfo[4] * MarketInfo(_ring[i][1], MODE_ASK) / MarketInfo(_ring[i][0], MODE_ASK);
        if(StringSubstr(_ring[i][0], 0, 3) == "EUR")
        {
            sinfo[1] *= MarketInfo("EURUSD", MODE_BID);
            sinfo[3] *= MarketInfo("EURUSD", MODE_BID);
            sinfo[5] *= MarketInfo("EURUSD", MODE_BID);
        }

        sinfo[6] = sinfo[1] + sinfo[3] + sinfo[5];

        for(int j = 0; j < 7; j++)
        {
            if(j==0 || j==2 || j==4)
                libVisualSetTextObj("swap_value_row_" + i + "_col_" + j, DoubleToStr(sinfo[j], 2), White);
            else
                libVisualSetTextObj("swap_value_row_" + i + "_col_" + j, DoubleToStr(sinfo[j], 2), C'0xe6,0xdb,0x74');
        }
    }
}

void updateAccountInfo()
{
    double ainfo[5];
    ainfo[0] = AccountBalance();
    ainfo[1] = AccountProfit();
    ainfo[2] = AccountEquity();
    ainfo[3] = AccountMargin();
    ainfo[4] = AccountFreeMargin();

    for(int i = 0; i < 5; i++)
        libVisualSetTextObj("account_value_col_" + i, DoubleToStr(ainfo[i], 2), White);
}

void updateLogStatusInfo(int _aid)
{
    libVisualSetTextObj("log_price_data_date", libDatetimeGetDate(TimeLocal()), GreenYellow);

    if(checkOrderLogStatus(_aid) == true)
        libVisualSetTextObj("log_price_data_status", "Logged");
    else 
        libVisualSetTextObj("log_price_data_status", "No Log");
}

void updateFpiInfo(double &_fpi[][7])
{
    int digit = 7;
    string prefix = "fpi_body_row_";
    string row = "", col = "";
    int spread = 0;

    for(int i = 0; i < RingNum; i++)    //-- row 5 to row 10
    {
        row = (i);
        
        spread  = MarketInfo(Ring[i][0], MODE_SPREAD);
        spread += MarketInfo(Ring[i][1], MODE_SPREAD);
        spread += MarketInfo(Ring[i][2], MODE_SPREAD);

        libVisualSetTextObj(prefix + row + "_col_4", DoubleToStr(_fpi[i][0], digit), DeepSkyBlue);
        libVisualSetTextObj(prefix + row + "_col_5", DoubleToStr(_fpi[i][1], digit));
        libVisualSetTextObj(prefix + row + "_col_6", DoubleToStr(_fpi[i][2], digit), DeepSkyBlue);
        libVisualSetTextObj(prefix + row + "_col_7", DoubleToStr(_fpi[i][3], digit));
        libVisualSetTextObj(prefix + row + "_col_10", spread);
        
        if(_fpi[i][4] > 0)
        {
            libVisualSetTextObj(prefix + row + "_col_8", DoubleToStr(_fpi[i][4], digit), C'0xe6,0xdb,0x74');
            libVisualSetTextObj(prefix + row + "_col_9", DoubleToStr(_fpi[i][5], digit), C'0xe6,0xdb,0x74');
        }
        else
        {
            libVisualSetTextObj(prefix + row + "_col_8", DoubleToStr(_fpi[i][4], digit));
            libVisualSetTextObj(prefix + row + "_col_9", DoubleToStr(_fpi[i][5], digit));
        }
        
        if(spread < RingSpread[i] || RingSpread[i] == 0)
            RingSpread[i] = spread;

        if(RingSpread[i] < 300 && nottradesingal == true)
            libDebugSendAlert(Ring[i][1] + " can trade now!");

        
        libVisualSetTextObj(prefix + row + "_col_11", RingSpread[i], C'0xe6,0xdb,0x74');
    }
}

void getFPI(double &_fpi[][7], string &_ring[][3])
{
    double l_price[3];
    double s_price[3];

    for(int i = 0; i < RingNum; i ++)
    {
        for(int x = 0; x < 3; x++)
        {
            if(x == 0)
            {
                l_price[x] = MarketInfo(_ring[i][x], MODE_ASK);
                s_price[x] = MarketInfo(_ring[i][x], MODE_BID);
            }
            else
            {
                l_price[x] = MarketInfo(_ring[i][x], MODE_BID);
                s_price[x] = MarketInfo(_ring[i][x], MODE_ASK);
            }
        }
        
        //-- long
        if(l_price[0] > 0 && l_price[1] > 0 && l_price[2] > 0)
        {
            _fpi[i][0] = l_price[0] / (l_price[1] * l_price[2]);
            //-- buy FPI history
            if(_fpi[i][1] == 0 || _fpi[i][0] < _fpi[i][1]) 
                _fpi[i][1] = _fpi[i][0];
        }
        else
            _fpi[i][0] = 0;

        //-- short
        if(s_price[0] > 0 && s_price[1] > 0 && s_price[2] > 0)
        {
            _fpi[i][2] = s_price[0] / (s_price[1] * s_price[2]);
            //-- sell FPI history
            if(_fpi[i][3] == 0 || _fpi[i][2] > _fpi[i][3]) 
                _fpi[i][3] = _fpi[i][2];
        }
        else
            _fpi[i][2] = 0;

        //-- sH-bL
        if(_fpi[i][6]==0 || _fpi[i][3] - _fpi[i][1] > _fpi[i][6])
            _fpi[i][6] = _fpi[i][3] - _fpi[i][1];

        //-- auto set fpi thold
        if(_fpi[i][6] >= 0.002 && _fpi[i][4] == 0 && _fpi[i][5] == 0 && _fpi[i][1] != 0 && _fpi[i][3] != 0)
        {
            _fpi[i][4] = _fpi[i][1]; //-- 
            _fpi[i][5] = _fpi[i][3]; //--
        }
    }
}

//-- log margin data to db
void logSafeMarginTest2Db()
{
    tm = TimeCurrent();
    if(std_t == 0)
        std_t = tm;
    else if((tm - std_t) > 200)
        std_t = tm;
    else if(tm >= std_t)
    {
        std_t += 60;

        string query = "insert into nst_ta_swap_safe_margin_note (logtime, profitloss, commission, accountnum, margin, freemargin, equity, swap, balance) values ('"+libDatetimeTm2str(tm)+"', "+test_pl+", "+test_commission+", "+AccountNumber()+", "+AccountMargin()+", "+AccountFreeMargin()+", "+AccountEquity()+", "+test_swap+", "+AccountBalance()+")";
        string res = pmql_exec(query);
    }

    test_pl = 0;
    test_commission = 0;
    test_swap = 0;
}





/*
 * Log Price and account info to pgsql
 *
 */

void logPriceInfo2Db()
{
    int currhour = TimeHour(TimeLocal());
    /*string currdate = libDatetimeTm2str(TimeLocal());
    currdate = StringSubstr(currdate, 0, 10);*/

    if(currhour > 15)
    {

        //-- insert new opened order and new closed order into database
        checkOrderChange(aid, MagicNumber);

        //-- log current order (available order) infarmation to database
        logOrderInfo(aid, MagicNumber);

        //-- log swap rate date to database
        logSwapRate(aid);
    }
}

int getAccountIdByAccountNum(int _an)
{
    string query = "SELECT id FROM nst_sys_account WHERE accountnumber=" + _an;
    string res = pmql_exec(query);
    int id = StrToInteger(StringSubstr(res, 3, -1));

    return(id);
}

void checkOrderChange(int _aid, int _mg)
{
    //-- update new closed order to db
    update2db(1, _mg);
    //-- update new opened order to db
    update2db(0, _mg);
}

bool checkOrderLogStatus(int _aid)
{
    string currdate = libDatetimeGetDate(TimeLocal());
    string query = "select id from nst_ta_swap_order_daily_settlement where accountid=" + _aid + " and logdatetime > '" + currdate + "'";
    string res = pmql_exec(query);
    if(StringLen(res)>0)
        return(true);
    else
        return(false);
}

int logOrderInfo(int _aid, int _mg)
{
    string currtime = libDatetimeTm2str(TimeLocal());
    if(checkOrderLogStatus(_aid) == true)
        return(1);

    int ordertotal = OrdersTotal();
    string query = "INSERT INTO nst_ta_swap_order_daily_settlement (accountid,orderticket,logdatetime,currentprice,profit,swap) VALUES ";

    //-- order log
    for(int i = 0; i < ordertotal; i++)
    {
        if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
            if(OrderMagicNumber() == _mg)
            {
                query = StringConcatenate(
                    query,
                    "(" + _aid + ", " + OrderTicket() + ", '" + currtime + "', " + OrderClosePrice() + ", " + OrderProfit() + ", " + OrderSwap() + "),"
                );
            }
        }
    }
    query = StringSubstr(query, 0, StringLen(query) - 1);
    string res = pmql_exec(query);

    return(0);
}

//-- log swap rate to database
int logSwapRate(int _aid)
{
    string _symbols[5];
    _symbols[0] = "USDMXN";
    _symbols[1] = "EURMXN";
    _symbols[2] = "USDJPY";
    _symbols[3] = "EURJPY";
    _symbols[4] = "MXNJPY";

    double _longswap, _shortswap;

    string currtime = libDatetimeTm2str(TimeLocal());
    string currdate = StringSubstr(currtime, 0, 10);
    string query = "select id from nst_ta_swap_rate where accountid=" + _aid + " and logdatetime > '" + currdate + "'";
    string res = pmql_exec(query);
    if(StringLen(res)>0)
    {
        return(1);
    }

    query = "INSERT INTO nst_ta_swap_rate (accountid,symbol,longswap,shortswap,logdatetime) VALUES ";

    for(int i = 0; i < ArraySize(_symbols); i++)
    {
        _longswap  = MarketInfo(_symbols[i], MODE_SWAPLONG);
        _shortswap = MarketInfo(_symbols[i], MODE_SWAPSHORT);

        query = StringConcatenate(
            query,
            "(" + _aid + ", '" + _symbols[i] + "', " + _longswap + ", " + _shortswap + ", '" + currtime + "'),"
        );
    }

    query = StringSubstr(query, 0, StringLen(query) - 1);

    //libDebugOutputLog(query, "PGSQL");

    res = pmql_exec(query);

    return(0);
}


//-- format order array from 2 range to 1 range which query from pgsql and trans data type from string to int
void formatOrderArr(string _sourcearr[][], int &_targetarr[])
{
    int itemnum = ArraySize(_sourcearr);
    ArrayResize(_targetarr, itemnum);

    if(itemnum > 0)
    {
        for(int i = 0; i < itemnum; i++)
        {
            _targetarr[i] = StrToInteger(_sourcearr[i][0]);
        }
    }
}

//-- insert new opened order and new closed order into database
void update2db(int _type, int _mg)
{
    int i;
    //-- load orders ticket from metatrader
    int ordertickets[]; //-- order ticket in metatrader
    int realticketnum = 0; //-- the real size of otinmt array
    int ordertotal; //-- order history total
    if(_type == 1)
        ordertotal = OrdersHistoryTotal();
    else if(_type == 0)
        ordertotal = OrdersTotal();

    //-- adjust otinmt array size but not final adjust
    ArrayResize(ordertickets, ordertotal);

    if(ordertotal > 0)
    {
        for(i = 0; i < ordertotal; i++)
        {
            //-- check closed order 
            if(_type == 1)
            {
                if(OrderSelect(i, SELECT_BY_POS, MODE_HISTORY))
                {
                    if(OrderMagicNumber() == _mg && (OrderType()==OP_BUY || OrderType()==OP_SELL))
                    {
                        ordertickets[realticketnum] = OrderTicket();
                        realticketnum++;
                    }
                }
            }
            //-- check opened order 
            else if(_type == 0)
            {
                if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
                {
                    if(OrderMagicNumber() == _mg)
                    {
                        ordertickets[realticketnum] = OrderTicket();
                        realticketnum++;
                    }
                }
            }
        }
        ArrayResize(ordertickets, realticketnum); //-- final resize
    }
    else
    {
        libDebugSendAlert("No order find, maybe there is no closed order yet or the history period was set wrong.","Notifi<" + account + ">log2pgsql");
    }
    
    //libDebugArrDump(ordertickets);

    //-- load closed orders info from db
    string sdata[,1];
    int idata[];
    int rows = 0;
    string query = "select orderticket from nst_ta_swap_order where orderstatus=" + _type;
    string res = pmql_exec(query);

    if(StringLen(res) > 0)
    {
        libPgsqlFetchArr(res, sdata);
        rows = ArraySize(sdata);
        //libDebugOutputLog(rows, "Debug");
        formatOrderArr(sdata, idata);
    }

    //-- if no order in database
    if(rows == 0)
    {
        if(realticketnum > 0)
        {
            for(i = 0; i < realticketnum; i++)
            {
                if(_type == 1)
                    update2closed(ordertickets[i]);
                else if(_type == 0)
                    insert2opened(ordertickets[i]);
            }
        }
    }

    //-- 
    if(realticketnum > 0 && rows > 0)
    {
        for(i = 0; i < realticketnum; i++)
        {
            if(!libDebugInArr(ordertickets[i], idata))
            {
                for(i = 0; i < realticketnum; i++)
                {
                    if(_type == 1)
                    {
                        Print(ordertickets[i]);
                        update2closed(ordertickets[i]);
                    }
                    else if(_type == 0)
                        insert2opened(ordertickets[i]);
                }
            }
        }
    }
}

//-- update order status to closed to db by order ticket
int update2closed(int _oid)
{
    if(!OrderSelect(_oid, SELECT_BY_TICKET, MODE_HISTORY))
    {
        libDebugOutputLog("There was not find this history order [" + _oid + "], please check.", "Err");
        return(1);
    }

    string closetime = libDatetimeTm2str(OrderCloseTime());

    string query = "UPDATE nst_ta_swap_order SET orderstatus=1, closedate='" + closetime + "', getswap=" + OrderSwap() + ", closeprice=" + OrderClosePrice() + ", endprofit=" + OrderProfit() + ",commission=" + OrderCommission() + " WHERE orderticket=" + _oid;
    string res = pmql_exec(query);

    Print(query + " | " + res);
    if(libPgsqlIsError(res))
    {
        libDebugOutputLog("update history order status error [" + _oid + "], please check. " + query, "Err");
        
        insert2closed(_oid);
    }

    return(0);
}

//-- insert order status to closed to db by order ticket
int insert2closed(int _oid)
{
    if(!OrderSelect(_oid, SELECT_BY_TICKET, MODE_HISTORY))
    {
        libDebugOutputLog("There was not find this history order [" + _oid + "], please check.", "Err");
        return(1);
    }

    string closetime = libDatetimeTm2str(OrderCloseTime());
    string opentime = libDatetimeTm2str(OrderOpenTime());

    string query = "INSERT INTO nst_ta_swap_order (userid,orderticket,usemargin,opendate,orderstatus,closedate,getswap,ordertype,openprice,commission,closeprice,endprofit) VALUES (1," + _oid + ",0,'" + opentime + "',1,'" + closetime + "'," + OrderSwap() + "," + OrderType() + "," + OrderOpenPrice() + "," + OrderCommission() + "," + OrderClosePrice() + "," + OrderProfit() + ")";
    string res = pmql_exec(query);

    if(libPgsqlIsError(res))
        libDebugOutputLog("inster into closed order status error [" + _oid + "], please check. "+query, "Err");
    else
        libDebugOutputLog("inster into closed order OK", "Status");

    return(0);
}

//-- insert new opened order to database;
int insert2opened(int _oid)
{
    if(!OrderSelect(_oid, SELECT_BY_TICKET, MODE_TRADES))
    {
        libDebugOutputLog("There was not find this opened order [" + _oid + "], please check.", "Err");
        return(1);
    }

    string opentime = libDatetimeTm2str(OrderOpenTime());

    string query = "INSERT INTO nst_ta_swap_order (userid,orderticket,usemargin,opendate,orderstatus,ordertype,openprice,commission) VALUES (1," + _oid + ",0,'" + opentime + "',0," + OrderType() + "," + OrderOpenPrice() + "," + OrderCommission() + ")";
    string res = pmql_exec(query);

    if(libPgsqlIsError(res))
        libDebugOutputLog("inster into opened order status error [" + _oid + "], please check. "+query, "Err");
    else
        libDebugOutputLog("inster into opened order OK", "Status");

    return(0);
}