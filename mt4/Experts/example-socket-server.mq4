//+------------------------------------------------------------------+
//|                                                      ProjectName |
//|                                      Copyright 2012, CompanyName |
//|                                       http://www.companyname.net |
//+------------------------------------------------------------------+
/* ###################################################################

Example socket server.
Code can be used as both MQ4 and MQ5 (on both 32-bit and 64-bit MT5)

Receives messages from the example client and simply writes them
to the Experts log.

Also contains functionality for handling files sent by the example 
file-sender script.

In addition, you can telnet into the server's port. Any CRLF-terminated
message you type is similarly printed to the Experts log. You
can also type in the commands "quote", to which the server reponds
with the current price of its chart, or "close", which causes the
server to shut down the connection.

As well as demonstrating server functionality, the use of Receive()
and the event-driven handling are also applicable to a client
which needs to receive data from the server as well as just sending it.

################################################################### */
int TF=0; //timeframe for newbar
bool Newbar_flag=False; //new bar flag
#include <stderror.mqh>
#include <stdlib.mqh>



input string             InpFileName="ticks.csv";       // File name -> EURUSD_ticks.csv
input string             InpDirectoryName="Data";     // Folder name MQL4\Files\Data
input string             TicksSubscribe="/EURUSD/AUDUSD/GBPUSD/USDCAD/USCHF/USDJPY/";     // Subscribe currency quote
input int                MaxTickFileSize_kB = 1014*1024;  //  Ticks file size [kB]
input int                MaxTicksinMemory = 100000;  //  Number of ticks in memory
input bool               Archive_tick_file = True; // Archive old tick files
input bool               ReadTicksfromFile = True; // Read ticks from file
double prev_tick_bid[],prev_tick_ask[];
int tick_count[];
int symbol_number;
string symbol_name[];


string Tick_Memory[];

string header="Data|Timestamp|Bid price|Ask price|Volume\r\n";
string  Session="Standby";
string  Session1="Turn off collecting ticks";

string rx = "##"; 
string rn = "\r\n";


#property strict

// --------------------------------------------------------------------
// Include socket library, asking for event handling
// --------------------------------------------------------------------

#define SOCKET_LIBRARY_USE_EVENTS
#include <socket-library-mt4-mt5.mqh>

// --------------------------------------------------------------------
// EA user inputs
// --------------------------------------------------------------------

input ushort   ServerPort=23457;  // Server port
input int      TIMER_FREQ_MS=100;  //TIMER_FREQUENCY_MS
                                  // --------------------------------------------------------------------
// Global variables and constants
// --------------------------------------------------------------------

// Frequency for EventSetMillisecondTimer(). Doesn't need to 
// be very frequent, because it is just a back-up for the 
// event-driven handling in OnChartEvent()
#define  TIMER_FREQUENCY_MS    TIMER_FREQ_MS

// Server socket
ServerSocket*glbServerSocket=NULL;

// Array of current clients
ClientSocket*glbClients[];

// Watch for need to create timer;
bool glbCreatedTimer=false;
// --------------------------------------------------------------------
// Initialisation - set up server socket
// --------------------------------------------------------------------

void OnInit()
  {



// If the EA is being reloaded, e.g. because of change of timeframe,
// then we may already have done all the setup. See the 
// termination code in OnDeinit.
   if(glbServerSocket)
     {
      Print("Reloading EA with existing server socket");
        } else {
      // Create the server socket
      glbServerSocket=new ServerSocket(ServerPort,false);
      if(glbServerSocket.Created())
        {
         Print("Server socket created");

         // Note: this can fail if MT4/5 starts up
         // with the EA already attached to a chart. Therefore,
         // we repeat in OnTick()
         glbCreatedTimer=EventSetMillisecondTimer(TIMER_FREQUENCY_MS);
           } else {
         Print("Server socket FAILED - is the port already in use?");
        }
     }
  }
// --------------------------------------------------------------------
// Termination - free server socket and any clients
// --------------------------------------------------------------------

void OnDeinit(const int reason)
  {
   switch(reason)
     {
      case REASON_CHARTCHANGE :
         // Keep the server socket and all its clients if 
         // the EA is going to be reloaded because of a 
         // change to chart symbol or timeframe 
         
         
         break;

      default:
         // For any other unload of the EA, delete the 
         // server socket and all the clients 
         glbCreatedTimer=false;

         // Delete all clients currently connected
         for(int i=0; i<ArraySize(glbClients); i++)
           {
            delete glbClients[i];
           }
         ArrayResize(glbClients,0);

         // Free the server socket. *VERY* important, or else
         // the port number remains in use and un-reusable until
         // MT4/5 is shut down
         delete glbServerSocket;
         Print("Server socket terminated");
         break;
     }
  }
// --------------------------------------------------------------------
// Timer - accept new connections, and handle incoming data from clients.
// Secondary to the event-driven handling via OnChartEvent(). Most
// socket events should be picked up faster through OnChartEvent()
// rather than being first detected in OnTimer()
// --------------------------------------------------------------------

void OnTimer()
  {


// Accept any new pending connections
   AcceptNewConnections();

// Process any incoming data on each client socket,
// bearing in mind that HandleSocketIncomingData()
// can delete sockets and reduce the size of the array
// if a socket has been closed

   for(int i=ArraySize(glbClients)-1; i>=0; i--)
     {
      HandleSocketIncomingData(i);
     }
     TickSaver();
     HUD();
     Session="Standby";
  }
// --------------------------------------------------------------------
// Accepts new connections on the server socket, creating new
// entries in the glbClients[] array
// --------------------------------------------------------------------

void AcceptNewConnections()
  {
// Keep accepting any pending connections until Accept() returns NULL
   ClientSocket*pNewClient=NULL;
   do
     {
      pNewClient=glbServerSocket.Accept();
      if(pNewClient!=NULL)
        {
         int sz=ArraySize(glbClients);
         ArrayResize(glbClients,sz+1);
         glbClients[sz]=pNewClient;
         Print("New client connection");

         pNewClient.Send("Client:" + sz);
        }

     }
   while(pNewClient!=NULL);
  }
// --------------------------------------------------------------------
// Handles any new incoming data on a client socket, identified
// by its index within the glbClients[] array. This function
// deletes the ClientSocket object, and restructures the array,
// if the socket has been closed by the client
// --------------------------------------------------------------------

void HandleSocketIncomingData(int idxClient)
  {
   ClientSocket*pClient=glbClients[idxClient];

// Keep reading CRLF-terminated lines of input from the client
// until we run out of new data
   bool bForceClose=false; // Client has sent a "close" message
   string strCommand;

   do
     {
     
      strCommand=pClient.Receive("");
      //if (strCommand!="")Print(strCommand);
//---------------------------------Bid/Ask REQUEST      
      if(StringFind(strCommand,"__BidAsk")==110)
        {      
            string SYMBOL=StringSubstr(strCommand,6,-1);
            string bidask;
            MqlTick last_tick;
            if(SymbolInfoTick(Symbol(),last_tick))
            {
            string timestamp=TimeToString(last_tick.time,TIME_DATE)+rx+TimeToString(last_tick.time,TIME_SECONDS)+rx+last_tick.time_msc%1000;
            
            //string header="Data|Timestamp|Bid price|Ask price|Volume\n";
            bidask=header+timestamp+";"+StringFormat("%5f|%5f|%5f",last_tick.bid,last_tick.ask,last_tick.volume);
            }
            pClient.Send(bidask);


//--------------------Subscribe_BidAsk   REQUEST
           } else if(StringFind(strCommand,"Subscribe_BidAsk/")==0) {
                  Session="Subscribe_BidAsk.";
                  string data=header;
                  int startpos=StringFind(strCommand,"/")+1;
                  int endpos = StringFind(strCommand,"/last_ticks:");
                  int lenght= endpos-startpos;
                  string SYMBOL=StringSubstr(strCommand,startpos,lenght);
                  Print(SYMBOL);Sleep(1);
                  startpos=endpos+12;
                  string LAST_TICKS=StringSubstr(strCommand,startpos,-1);
                  int last_ticks=StrToInteger(LAST_TICKS);
                  Print(LAST_TICKS);
                  //-----------
                  //Read ticks from memory first if enough
                  int mem_size = ArraySize(Tick_Memory);
                  if (mem_size>last_ticks)                  
                     {for (int i=0;i<last_ticks;i++)                  
                        data=data+Tick_Memory[i];
                  //else read from file                            
                  } else if (ReadTicksfromFile ){
                  Session=StringConcatenate(Session," .. Reading from tick file");
                  string file_name = SYMBOL+"_"+InpFileName;
                  string file_path = InpDirectoryName+"//"+file_name;                                              
                  int file_handle=FileOpen(file_path,FILE_READ|FILE_CSV|FILE_ANSI );
                  if(file_handle!=INVALID_HANDLE)
                  {  data="";
                     int    str_size;                      
                     int rows=0;                     
                     while(!FileIsEnding(file_handle))
                             {
                              //--- find out how many symbols are used for writing the time
                              str_size=FileReadInteger(file_handle,INT_VALUE);
                              //--- read the string 
                              data=data+FileReadString(file_handle,str_size)+"\r\n";
                              rows++;
                              if (rows>last_ticks*5)break; // 5 columns
                             }                  
                             Session=StringConcatenate(Session," .. Reading from tick completed");
                  
                     FileClose(file_handle);                  
                  }                          }
                  //Print(Tick_Memory[0]);
                  //Sleep(10000);
                  Session=StringConcatenate(Session," .. Sending data to Py"); 
                  pClient.Send(data);
                  
                  
//---OHCL REQUEST
           } else if(StringFind(strCommand,"Subscribe_OHLC:")==0) {
                  Session="Subscribe_OHLC.";
                  //Newbar_flag = True; //------------------------------------------------!!!!!!!!!!!!!!!!!!!!!
                  if (Newbar_flag=False) pClient.Send("NO DATA");
                  else{
                  int startpos=StringFind(strCommand,":")+1;
                  int endpos = StringFind(strCommand,"/timeframe:");
                  int lenght= endpos-startpos;
                  string SYMBOL=StringSubstr(strCommand,startpos,lenght);
                  //Print("SYMBOL:",SYMBOL);
                  startpos=endpos+11;
                  endpos=StringFind(strCommand,"/bars:");
                  lenght=endpos-startpos;
                  string TIMEFRAME=StringSubstr(strCommand,startpos,lenght);
                  //Print("TIMEFRAME:",TIMEFRAME);

                  startpos=endpos+6;
                  //lenght=endpos-startpos;
                  string BARS=StringSubstr(strCommand,startpos,-1);
                  //Print("BARS:",BARS);
                  //-----------------------------------

                  string data=GetOHLC(SYMBOL,StrToInteger(TIMEFRAME),StrToInteger(BARS));
                  pClient.Send(data);Newbar_flag=False;
                  Session=StringConcatenate(Session," .. Sending data to Py"); 
                  
                  }
                  

         //message = symbol +  '/T:' + str(type) + '/L:' + str(lots) + '/P:' + str(price) + '/SL:' + str(SL) + '/TP:' + str(TP)+ '/M:' + str(magic) + '/C:'  + str(comment)


//---OrderSend COMMAND
//int  OrderSend(
//   string   symbol,              // symbol
//   int      cmd,                 // operation
//   double   volume,              // volume
//   double   price,               // price
//   int      slippage,            // slippage
//   double   stoploss,            // stop loss
//   double   takeprofit,          // take profit
//   string   comment=NULL,        // comment
//   int      magic=0,             // magic number
//   datetime expiration=0,        // pending order expiration
//   color    arrow_color=clrNONE  // color
//   );
           } else if(StringFind(strCommand,"OrderSend:")==0) {
                  Session=StringConcatenate(Session," .. Sending OrderSend command");
                  int startpos=StringFind(strCommand,":")+1;
                  int endpos = StringFind(strCommand,"/type:");
                  int lenght= endpos-startpos;
                  string SYMBOL=StringSubstr(strCommand,startpos,lenght);
         
                  startpos=endpos+6;
                  endpos=StringFind(strCommand,"/lots:");
                  lenght=endpos-startpos;
                  string TYPE=StringSubstr(strCommand,startpos,lenght);
                  Print("TYPE:",TYPE);
         
                  startpos=endpos+6;
                  endpos=StringFind(strCommand,"/price:");
                  lenght=endpos-startpos;
                  string LOTS=StringSubstr(strCommand,startpos,lenght);
                  Print("Lots:",LOTS);
         
                  startpos=endpos+7;
                  endpos=StringFind(strCommand,"/SL:");
                  lenght=endpos-startpos;
                  string PRICE=StringSubstr(strCommand,startpos,lenght);
                  Print("Price:",PRICE);
         
                  startpos=endpos+4;
                  endpos=StringFind(strCommand,"/TP:");
                  lenght=endpos-startpos;
                  string SL=StringSubstr(strCommand,startpos,lenght);
                  Print("SL:",SL);
         
                  startpos=endpos+4;
                  endpos=StringFind(strCommand,"/magic:");
                  lenght=endpos-startpos;
                  string TP=StringSubstr(strCommand,startpos,lenght);
                  Print("TP:",TP);
         
                  startpos=endpos+7;
                  endpos=StringFind(strCommand,"/comm:");
                  lenght=endpos-startpos;
                  string Magic=StringSubstr(strCommand,startpos,lenght);
                  Print("Magic:",Magic);
         
                  startpos=endpos+6;
                  //lenght=endpos-startpos;
                  string Comm=StringSubstr(strCommand,startpos,-1);
                  Print("Comment:",Comm);
                  //--------------
                  int d=MarketInfo(SYMBOL,MODE_DIGITS);
                  double price; int type ;
                  if (PRICE!="Ask" || PRICE!="Bid") price = NormalizeDouble(StringToDouble(PRICE),d);
                  if (TYPE=="OP_BUY" || TYPE=="0"){price = Ask; type = 0;}
                  if (TYPE=="OP_SELL" || TYPE=="1"){price = Bid; type = 1;}
                  string data;
                  string error="ok";
                  double OrdOpenPrice=0;
                  int ticket=-1;
                  
                  ticket=OrderSend(SYMBOL,type,LOTS,price,3,NormalizeDouble(StringToDouble(SL),d),NormalizeDouble(StringToDouble(TP),d),Comm,StringToInteger(Magic),0,Blue);
                  
                  if(ticket>0)
                    {
                     Print("Order opened_",TYPE,Comm);
                     if(OrderSelect(ticket,SELECT_BY_TICKET)==true)
                        OrdOpenPrice=OrderOpenPrice();
                     else
                        Print("OrderSelect returned the error of ",GetLastError());
                    }
                  else
                    {
                     int check=GetLastError();
                      error="Error "+check+": "+ErrorDescription(check);
                     Print(error);
                     OrdOpenPrice=-1;
                     ticket = -1;
                     //data = error; 
                    }

                  
                  data=IntegerToString(ticket)+rx+DoubleToStr(OrdOpenPrice,5)+rx+error+"\n" ;       
                  //data=IntegerToString(124678)+rx+DoubleToStr(1.52432,5)+rx+"ok"+"\n"  ;              //!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!              
                  Print("data",data);
                  pClient.Send(data);

                  Session=StringConcatenate(Session," .. OrderSend sent...");
                  
//---OrderClose COMMAND
 //bool  OrderClose(
 //  int        ticket,      // ticket
 //  double     lots,        // volume
 //  double     price,       // close price
 //  int        slippage,    // slippage
 //  color      arrow_color  // color
 //  )
           } else if(StringFind(strCommand,"OrderClose:")==0) {
                  Session=StringConcatenate(Session," .. OrderClose request");
                  string SYMBOL="NONE";
                  int d=5; //digits
                  int startpos=StringFind(strCommand,":")+1;
                  int endpos = StringFind(strCommand,"/lots:");
                  int lenght= endpos-startpos;
                  string TICKET=StringSubstr(strCommand,startpos,lenght);

                  startpos=endpos+6;
                  endpos=StringFind(strCommand,"/price:");
                  lenght=endpos-startpos;
                  string LOTS=StringSubstr(strCommand,startpos,lenght);
                  LOTS = StrToDouble(LOTS);                                    
                  Print("Lots:",LOTS);
                  
                  startpos=endpos+7;
                  //lenght=endpos-startpos;
                  string PRICE=StringSubstr(strCommand,startpos,-1);
                  Print("PRICE:",PRICE);
                  
                  //--------------
                  
                  if(OrderSelect(StrToInteger(TICKET),SELECT_BY_TICKET)==true && LOTS==0)LOTS=OrderLots();

                  string data;
                  string error="ok";
                  double OrdClosePrice=0;
                  
                  bool res=OrderClose(TICKET,LOTS,PRICE,3,Blue);
                  if(res)
                    {
                     Print("Order closed",TICKET);
                     if(OrderSelect(StrToInteger(TICKET),SELECT_BY_TICKET,MODE_HISTORY)==true){
                        OrdClosePrice=OrderClosePrice();
                        SYMBOL=OrderSymbol();
                                        }
                     else
                        Print("OrderSelect returned the error of ",GetLastError());
                    }
                  else
                    {
                     int check=GetLastError();
                      error="Error "+check+": "+ErrorDescription(check);
                     Print(error);
                     OrdClosePrice=-1;
                     
                     //data = error; 
                    }
                  d=MarketInfo(SYMBOL,MODE_DIGITS);
                   
                  data=IntegerToString(TICKET)+rx+DoubleToStr(OrdClosePrice,d)+rx+error+"\n" ; 
                  //data=IntegerToString(124678)+rx+DoubleToStr(1.52232,d)+rx+"ok"+"\n"  ; //!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
                         
                  pClient.Send(data);
                  Session=StringConcatenate(Session," .. OrderClose sent"); 
                  
//---Account Info REQEST
           } else if(StringFind(strCommand,"ala")>=0) {
                  double Balance =  AccountBalance();
                  string data=DoubleToStr(Balance,2)+rn ; 
                         
                  pClient.Send(data);
                  Session=StringConcatenate(Session," .. AccountBalance info sent"); 
                 
                  
           } else if(StringFind(strCommand,"quity")>=0) {
                  double Equity =  AccountEquity();
                  string data=DoubleToStr(Equity,2)+rn ; 
                         
                  pClient.Send(data);
                  Session=StringConcatenate(Session," .. AccountEquity info sent"); 
                  
           } else if(StringFind(strCommand,"urr")>=0) {
                  string Curr =  AccountCurrency();
                  string data=Curr +rn ;
                  Print(data); 
                         
                  pClient.Send(data);
                  Session=StringConcatenate(Session," .. AccountCurrency info sent"); 

//---CLOSE CONNECTION 
           } else if(strCommand=="close") {
         bForceClose=true;

           } 
        //   else if(strCommand!="") {
        // // Potentially handle other commands etc here.
        // // For example purposes, we'll simply print messages to the Experts log
        // Print("<- ",strCommand);
        // Print("Unknow command");
        // pClient.Send("Unknow command");
        //}
     }
   while(strCommand!="");

// If the socket has been closed, or the client has sent a close message,
// release the socket and shuffle the glbClients[] array
   if(!pClient.IsSocketConnected() || bForceClose)
     {
      Print("Client has disconnected");

      // Client is dead. Destroy the object
      delete pClient;

      // And remove from the array
      int ctClients=ArraySize(glbClients);
      for(int i=idxClient+1; i<ctClients; i++)
        {
         glbClients[i-1]=glbClients[i];
        }
      ctClients--;
      ArrayResize(glbClients,ctClients);
     }
  }
// --------------------------------------------------------------------
// Use OnTick() to watch for failure to create the timer in OnInit()
// --------------------------------------------------------------------

void OnTick()
  {

   if(!glbCreatedTimer) glbCreatedTimer=EventSetMillisecondTimer(TIMER_FREQUENCY_MS);
   if(IsNewBar(0,TF))Newbar_flag=true; else  Newbar_flag=False;
   

 

  }
// --------------------------------------------------------------------
// Event-driven functionality, turned on by #defining SOCKET_LIBRARY_USE_EVENTS
// before including the socket library. This generates dummy key-down
// messages when socket activity occurs, with lparam being the 
// .GetSocketHandle()
// --------------------------------------------------------------------

void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
  {
   if(id==CHARTEVENT_KEYDOWN)
     {
      // If the lparam matches a .GetSocketHandle(), then it's a dummy
      // key press indicating that there's socket activity. Otherwise,
      // it's a real key press

      if(lparam==glbServerSocket.GetSocketHandle())
        {
         // Activity on server socket. Accept new connections
         Print("New server socket event - incoming connection");
         AcceptNewConnections();

           } else {
         // Compare lparam to each client socket handle
         for(int i=0; i<ArraySize(glbClients); i++)
           {
            if(lparam==glbClients[i].GetSocketHandle())
              {
               HandleSocketIncomingData(i);
               return; // Early exit
              }
           }

         // If we get here, then the key press does not seem
         // to match any socket, and appears to be a real
         // key press event...
        }
     }
  }
  
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
string   GetOHLC(string symbol,int timeframe,int bars)
  {


   MqlRates rates[];
   ArraySetAsSeries(rates,true);
   //bars=bars+1;
   string header_OHLC="Data"+rx+"Timestamp"+rx+"Open"+rx+"High"+rx+"Low"+rx+"Close"+rx+"Volume"+rn;
   string out="";
   int copied =0;
           
   copied=CopyRates(symbol,timeframe,1,bars+1,rates);
  // Print("copied",bars);
  
     
      for(int j=bars; j>=0; j--)
        {
        
         out=   out+ (
                      TimeToString(rates[j].time,TIME_DATE)+rx+
                      TimeToString(rates[j].time,TIME_SECONDS)+rx+
                      DoubleToString(rates[j].open)+rx+
                      DoubleToString(rates[j].high)+rx+
                      DoubleToString(rates[j].low)+rx+
                      DoubleToString(rates[j].close)+rx+
                      DoubleToString(rates[j].tick_volume)
                     +"\n");
         
         //continue;
      
        }
        
   out = header_OHLC+out;
   //Print(out);
   return(out);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool IsNewBar(int mode=0,int period=0)
  {
//0 - при первом запуске возвращает true
//1 - при первом запуске ожидает следующий бар
   static datetime tm[10];
   int t=tfA(period);
   if(tm[t]==0&&mode==1) tm[t]=iTime(_Symbol,period,0);
   if(tm[t]==iTime(_Symbol,period,0)) return (false);
   tm[t]=iTime(_Symbol,period,0);
   return (true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int tfA(int tf)
  {
   switch(tf)
     {
      case PERIOD_M1: return (0);
      case PERIOD_M5: return (1);
      case PERIOD_M15: return (2);
      case PERIOD_M30: return (3);
      case PERIOD_H1: return (4);
      case PERIOD_H4: return (5);
      case PERIOD_D1: return (6);
      case PERIOD_W1: return (7);
      case PERIOD_MN1: return (8);
      default: return (9);
     }
  }
//+------------------------------------------------------------------+
void TickSaver()    
         
{
if (ArraySize(prev_tick_bid)==0){
ArrayResize(prev_tick_bid,100,100);
ArrayResize(prev_tick_ask,100,100);
ArrayResize(tick_count,100,100);
ArrayResize(symbol_name,100,100);
}

         string SYMBOLS = TicksSubscribe;
         int begin=0;
         int end=1;
         symbol_number=0;
         while(True)
            {
               //TicksSubscribe="|EURUSD|GBPUSD|USDJPY|                
               
               begin=StringFind(SYMBOLS,"/",end-1);               
               end=StringFind(SYMBOLS,"/",begin+1);              
               //Print(begin,"/",end);        
               string SYMBOL=StringSubstr(SYMBOLS,begin+1,end-begin-1);
               
               if (end<0)break;
               symbol_number++;
               symbol_name[symbol_number]=SYMBOL;
                
               //Print(SYMBOL,symbol_number);
               string bidask;
               MqlTick last_tick;

               
               
               if(SymbolInfoTick(SYMBOL,last_tick)){
                   
                  if (prev_tick_bid[symbol_number]!=last_tick.bid || prev_tick_ask[symbol_number]!=last_tick.ask)tick_count[symbol_number]=tick_count[symbol_number]+1;
                  prev_tick_bid[symbol_number]=last_tick.bid; prev_tick_ask[symbol_number]=last_tick.ask;
                  
                  string timestamp=TimeToString(last_tick.time,TIME_DATE)+"|"+TimeToString(last_tick.time,TIME_SECONDS)+":"+StringFormat("%d|",last_tick.time_msc%1000);
                  bidask=timestamp+StringFormat("%5f|%5f|%2f",last_tick.bid,last_tick.ask,last_tick.volume)+"\r\n";
                                                     } 
               //----Copy tick bidask to the end memory
                
               int size = DynamicArray(Tick_Memory,bidask,MaxTicksinMemory) ;
                              
               //Print("Memory Size",size);                                    
               

                    
               //---Saving to file               
               string time = IntegerToString(TimeCurrent());
               string file_name = SYMBOL+"_"+InpFileName;
               string file_archive = SYMBOL +"_" + time + "_" + InpFileName;
               string file_path = InpDirectoryName+"//"+file_name;
               string file_parch = InpDirectoryName+"//"+file_archive; 
                                            
               int file_handle=FileOpen(file_path,FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI,"|" );
               if(file_handle!=INVALID_HANDLE){ 
               
               //---Header in first line
               
               //string header="Data|Timestamp|Bid price|Ask price|Volume\r\n";
               if (FileSize(file_handle)==0)
               {FileSeek(file_handle,0,SEEK_SET);
               FileWriteString(file_handle,header,StringLen(header));}

               FileSeek(file_handle,0,SEEK_END);
               FileWriteString(file_handle,bidask,StringLen(bidask));
       
               
               //---Archiving full ticks file
               if (FileSize(file_handle)> MaxTickFileSize_kB*1024 && Archive_tick_file)
               {Print("Tick File is too large");
                 FileClose(file_handle);  
                  bool copy = FileCopy(file_path,0,file_parch,FILE_REWRITE  );  
               if(copy)
                  {Print("Ticks file is copied!");                  
                  if (FileDelete(file_path,0));
                  }
               else
                  Print("Ticks File is not copied!");              
                 } 
                                 
               FileClose(file_handle);

               }
               Session1="Saving ticks..."+TicksSubscribe;
               //Print(SYMBOL, " Data saved"); 
            
         }
}

void HUD(){

   Comment(	"*=====================*",
            "\n   "+Session,
            "\n   "+Session1,
            "\n   Symbol / ticks: "+symbol_name[1]+" "+tick_count[1],
            "\n   Symbol / ticks: "+symbol_name[2]+" "+tick_count[2],             
            "\n   Symbol / ticks: "+symbol_name[3]+" "+tick_count[3],
            "\n   Symbol / ticks: "+symbol_name[4]+" "+tick_count[4],
            "\n   Symbol / ticks: "+symbol_name[5]+" "+tick_count[5],
            "\n   Symbol / ticks: "+symbol_name[6]+" "+tick_count[6], 
            "\n   Symbol / ticks: "+symbol_name[7]+" "+tick_count[7],             
				"\n    MT4 <-> Python",
				"\n     EA_Version 1.00",
				"\n*=====================*");
//				
//				"\n    Magic Number       = "+Magic,
//				//"\n*=====================*",
//				//"\n    "+Session,
//				"\n*=====================*",
//				"\n    Spreads:",
//				"\n    actual/median/max = ",DoubleToStr((Ask-Bid)/PointValue,1),
//				"\n*=====================*",	RiskMode,
//				"\n    Lot Size                = ",DoubleToStr(CalculateLots(Risk),2),
//				"\n    Optimal F Lot       = ",DoubleToStr(Kellylot,2),  " Kelly = " + Kelly_yes ,
//				"\n    Leverage              = 1:",AccountLeverage(),
//				"\n    Added Cash          = ",DoubleToStr(Add_Cash,2),				
//				"\n*=====================*",
//				"\n    Total Profit (Loss)   = ",DoubleToStr(HistoryProfit()+MarketProfit(),2),
//				"\n    Market Profit (Loss)   = ",DoubleToStr(MarketProfit(),2),
//				"\n*=====================*"
//            "\n    WPR   =  " + DoubleToStr(WPR_2,2),  " || " + DoubleToStr(WPR_1,2),
//           // "\n    WPR Entry  =  " + DoubleToStr(WPR_1,2),
//            "\n    Exit   Buy   Sell | Entry  Buy   Sell",
//            "\n          >" + DoubleToStr(-WPR_Exit,0),"   <" + DoubleToStr((-100+WPR_Exit),0),"          <" + DoubleToStr(-WPR_Entry,0),"  >" + DoubleToStr((100-WPR_Entry),0),
//            "\n    Fractals Buy= "+ Fractals_Buy_Sig,"  Sell=   "+ Fractals_Sell_Sig,
//				"\n    CCI  =  " + DoubleToStr(CCI_2,2)," || " + DoubleToStr(CCI_1,2), 
//				//"\n    CCI Entry  =  " + DoubleToStr(CCI_1,2),
//            "\n    Exit   Buy   Sell | Entry  Buy   Sell",
//            "\n         >" + DoubleToStr(CCI_Exit,0),"  <" + DoubleToStr(-CCI_Exit,0),"        <" + DoubleToStr(-CCI_Entry,0),"  >" + DoubleToStr(CCI_Entry,0),           
//            "\n*=====================*"
//            "\n    Broker Time          = ",TimeToStr(TimeCurrent(), TIME_MINUTES|TIME_SECONDS),
//				"\n    GMT Time            = ",TimeToStr(TimeCurrent()-GMT_Offset*3600,TIME_MINUTES|TIME_SECONDS),
//				"\n    GMT Offset          = ",GMT_Offset,
//				"\n    Start  Broker/GMT = ",DoubleToHHMM(Open_Hour)," / ",DoubleToHHMM(GMT_Open_Hour),
//				"\n    End   Broker/GMT = ",DoubleToHHMM(Close_Hour)," / ",DoubleToHHMM(GMT_Close_Hour),
//            "\n*=====================*"
//            ,
//            DAAAAASH + EANAME +ln+
//            DAAAAASH + COMMENT
            
				
				//"\n",
				
}		

///----------------------------------------------------

int DynamicArray(  string &theArray[],string  value,int     maxLength )
{   int newSize = ArraySize( theArray ) + 1;
    ArraySetAsSeries( theArray, false );     // Normalize the array (left to right)
    ArrayResize(      theArray, newSize );   // Extend array length

    theArray[newSize-1] = value;             // Insert the new value

    ArraySetAsSeries( theArray, true );      // Reverse the array again

    if (  maxLength > 0
       && newSize   > maxLength )            // Check if the max length is reached
    {     newSize   = maxLength;
          ArrayResize( theArray, maxLength );
    }
    
    return( newSize );
}	

int DynamicArrayORG(  string &theArray[],string  value,int     maxLength )
{   int newSize = ArraySize( theArray ) + 1;
    ArraySetAsSeries( theArray, false );     // Normalize the array (left to right)
    ArrayResize(      theArray, newSize );   // Extend array length

    theArray[newSize-1] = value;             // Insert the new value

    ArraySetAsSeries( theArray, true );      // Reverse the array again

    if (  maxLength > 0
       && newSize   > maxLength )            // Check if the max length is reached
    {     newSize   = maxLength;
          ArrayResize( theArray, maxLength );
    }
    return( newSize );
}			