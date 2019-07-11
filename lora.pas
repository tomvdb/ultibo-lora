unit lora;

{ Lora Library for Ultibo, should support all rfm9x modules, but only tested with rfm98
Tom Van den Bon - July 2019
 Partially ported from Arduino library written by Sandeep Mistry - https://github.com/sandeepmistry/arduino-LoRa
 - spreading factor 7
 - signal bandwidth 125E3Hz
 - coding rate 5
 - preamble length 8
 - sync word 0x12
 - no crc

 lora unit connected to spi0
}


{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils,
  GlobalConst,
  Devices,
  SPI;

const

REG_FIFO                 =$00;
REG_OP_MODE              =$01;
REG_FRF_MSB              =$06;
REG_FRF_MID              =$07;
REG_FRF_LSB              =$08;
REG_PA_CONFIG            =$09;
REG_LNA                  =$0c;
REG_FIFO_ADDR_PTR        =$0d;
REG_FIFO_TX_BASE_ADDR    =$0e;
REG_FIFO_RX_BASE_ADDR    =$0f;
REG_FIFO_RX_CURRENT_ADDR =$10;
REG_IRQ_FLAGS            =$12;
REG_RX_NB_BYTES          =$13;
REG_PKT_SNR_VALUE        =$19;
REG_PKT_RSSI_VALUE       =$1a;
REG_MODEM_CONFIG_1       =$1d;
REG_MODEM_CONFIG_2       =$1e;
REG_PREAMBLE_MSB         =$20;
REG_PREAMBLE_LSB         =$21;
REG_PAYLOAD_LENGTH       =$22;
REG_MODEM_CONFIG_3       =$26;
REG_FREQ_ERROR_MSB       =$28;
REG_FREQ_ERROR_MID       =$29;
REG_FREQ_ERROR_LSB       =$2a;
REG_RSSI_WIDEBAND        =$2c;
REG_DETECTION_OPTIMIZE   =$31;
REG_DETECTION_THRESHOLD  =$37;
REG_SYNC_WORD            =$39;
REG_DIO_MAPPING_1        =$40;
REG_VERSION              =$42;

 // modes
MODE_LONG_RANGE_MODE     =$80;
MODE_SLEEP               =$00;
MODE_STDBY               =$01;
MODE_TX                  =$03;
MODE_RX_CONTINUOUS       =$05;
MODE_RX_SINGLE           =$06;

 // PA config
PA_BOOST                 =$80;

 // IRQ masks
IRQ_TX_DONE_MASK           =$08;
IRQ_PAYLOAD_CRC_ERROR_MASK =$20;
IRQ_RX_DONE_MASK           =$40;

MAX_PKT_LENGTH           =255;

type
 TLORA_ReadBytes = array[0..6] of Byte;
 LORA_ReadData =  ^TLORA_ReadBytes;

function  loraStart(frequency:Uint64) : integer;
procedure loraSleep();
procedure loraIdle();

procedure loraSetFrequency(frequency:Uint64);

procedure loraExplicitHeaderMode();
procedure loraImplicitHeaderMode();
procedure loraBeginPacket();
procedure loraEndPacket();

function  loraAvailable() : integer;
function  loraParsePacket() : integer;
function  loraRead() : integer;

procedure loraWrite(data: array of Byte; size:integer);
procedure loraWriteLine(txt:AnsiString);

function  loraReadRegister(address:Byte): Byte;
function  loraWriteRegister(address:Byte;value:Byte): Byte;

implementation


var
    SPIDevice:PSPIDevice;
    _frequency:Uint64;
    _implicitHeaderMode:Byte;
    _packetIndex:integer;

function loraRead() : integer;
begin
     if (loraAvailable() > 0 ) then
     begin
         _packetIndex := _packetIndex + 1;
         loraRead:= loraReadRegister(REG_FIFO);
     end
     else
     begin
          loraRead:= -1;
     end;
end;
procedure loraWriteLine(txt:AnsiString);
var
     buffer : array of Byte;
     count : integer;
begin
  setLength(buffer,length(txt));

  for Count:= 1 to length(txt) do
      buffer[Count-1]:= Ord(txt[Count]);

  loraBeginPacket();
  loraWrite(buffer,length(txt));
  loraEndPacket();

end;

function loraAvailable() : integer;
begin
  loraAvailable := (loraReadRegister(REG_RX_NB_BYTES) - _packetIndex);
end;

procedure loraEndPacket();
begin
  // put in TX mode
  loraWriteRegister(REG_OP_MODE, MODE_LONG_RANGE_MODE or MODE_TX);

  // wait for TX done
  while ((loraReadRegister(REG_IRQ_FLAGS) and IRQ_TX_DONE_MASK) = 0) do
    sleep(5);

  // clear IRQ's
  loraWriteRegister(REG_IRQ_FLAGS, IRQ_TX_DONE_MASK);
end;
function loraParsePacket() : integer;
var
  packetLength:integer;
  irqFlags:byte;
begin
  packetLength := 0;
  loraExplicitHeaderMode();
  irqFlags := loraReadRegister(REG_IRQ_FLAGS);

  // clear irq;s
  loraWriteRegister(REG_IRQ_FLAGS, irqFlags);

  if  (irqFlags and IRQ_RX_DONE_MASK <> 0) and (irqFlags and IRQ_PAYLOAD_CRC_ERROR_MASK = 0)  then
  begin
    // received a packet

    _packetIndex := 0;

    packetLength := loraReadRegister(REG_RX_NB_BYTES);

    // set FIFO address to current RX address
    loraWriteRegister(REG_FIFO_ADDR_PTR, loraReadRegister(REG_FIFO_RX_CURRENT_ADDR));

    // put in standby mode
    loraIdle();

   end else if (loraReadRegister(REG_OP_MODE) <> 133) then
   begin
    // not currently in RX mode

    // reset FIFO address
    loraWriteRegister(REG_FIFO_ADDR_PTR, 0);

    // put in single RX mode
    loraWriteRegister(REG_OP_MODE, MODE_LONG_RANGE_MODE or MODE_RX_SINGLE);
  end;

  loraParsePacket := packetLength;

end;
procedure loraBeginPacket();
begin
  // put in standby mode
  loraIdle();
  loraExplicitHeaderMode();

  // reset FIFO address and paload length
  loraWriteRegister(REG_FIFO_ADDR_PTR, 0);
  loraWriteRegister(REG_PAYLOAD_LENGTH, 0);
end;
procedure loraExplicitHeaderMode();
begin
  _implicitHeaderMode := 0;
  loraWriteRegister(REG_MODEM_CONFIG_1, loraReadRegister(REG_MODEM_CONFIG_1) and $fe);
end;
procedure loraImplicitHeaderMode();
begin
  _implicitHeaderMode := 1;
  loraWriteRegister(REG_MODEM_CONFIG_1, loraReadRegister(REG_MODEM_CONFIG_1) or $01);
end;
function loraStart(frequency:Uint64) : integer;
begin
  { setup spi }
  SPIDevice:=PSPIDevice(DeviceFindByDescription('BCM2837 SPI0 Master'));

  if SPIDeviceStart(SPIDevice, SPI_MODE_4WIRE, 250000, SPI_CLOCK_PHASE_LOW, SPI_CLOCK_POLARITY_LOW) <> ERROR_SUCCESS then
  begin
       loraStart := 0;
  end;

  if loraReadRegister(REG_VERSION) <> $12 then
    loraStart := 0;

  { put in sleep mode }
  loraSleep();

  loraSetFrequency(frequency);

  loraWriteRegister(REG_FIFO_TX_BASE_ADDR, 0);
  loraWriteRegister(REG_FIFO_RX_BASE_ADDR, 0);

  // set LNA boost
  loraWriteRegister(REG_LNA, loraReadRegister(REG_LNA) or $03);

  // set auto AGC
  loraWriteRegister(REG_MODEM_CONFIG_3, $04);

  // set tx level
  loraWriteRegister(REG_PA_CONFIG, PA_BOOST or (17 - 2));

  // idle
  loraIdle();
  loraStart := 1;
end;
procedure loraIdle();
begin
  loraWriteRegister(REG_OP_MODE, MODE_LONG_RANGE_MODE or MODE_STDBY);
end;
procedure loraSleep();
begin
  loraWriteRegister(REG_OP_MODE, MODE_LONG_RANGE_MODE or MODE_SLEEP);
end;
procedure loraSetFrequency(frequency:Uint64);
var
    frf:Uint64;
begin
  _frequency := frequency;
     frf := Uint64((frequency << 19) div 32000000);

  loraWriteRegister(REG_FRF_MSB, Byte(frf >> 16));
  loraWriteRegister(REG_FRF_MID, Byte(frf >> 8));
  loraWriteRegister(REG_FRF_LSB, Byte(frf >> 0));
end;
procedure SPI_read_register(spiDevice:Pointer;RegAdress:Byte;LORAReadData:LORA_ReadData; size:byte);
var
   n_Bytes:LongWord;
begin
  n_Bytes:=0;
  LORAReadData^[0]:=RegAdress;
  LORAReadData^[0]:= LORAReadData^[0];
  if SPIDeviceWriteRead(spiDevice,SPI_CS_0,LORAReadData,LORAReadData,size,SPI_TRANSFER_NONE,n_Bytes) = ERROR_SUCCESS then
   begin
        {some sort of error handling required here}
   end;
end;
procedure loraWrite(data: array of Byte; size:integer);
var
   currentLen:integer;
   i:integer;
begin
     currentLen := loraReadRegister(REG_PAYLOAD_LENGTH);

     if ((currentLen + size) > MAX_PKT_LENGTH) then
        size := MAX_PKT_LENGTH - currentLen;

     for i:= 0 to size-1 do
     begin
       loraWriteRegister(REG_FIFO, data[i]);
     end;

     // update length
     loraWriteRegister(REG_PAYLOAD_LENGTH, currentLen + size);
end;

function singleTransfer( address:Byte;value:Byte) : Byte;
var
   LORAReadData  : LORA_ReadData;
begin
  LORAReadData  := AllocMem(2);

  LORAReadData^[1] := value;
  SPI_read_register(SPIDevice,address,LORAReadData,2);

  singleTransfer := LORAReadData^[1];
end;
function loraReadRegister(address:Byte): Byte;
begin
  loraReadRegister := singleTransfer(address and $7f, $00);
end;

function loraWriteRegister(address:Byte;value:Byte): Byte;
begin
  loraWriteRegister := singleTransfer(address or $80, value);
end;


end.

