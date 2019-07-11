# ultibo-lora
Lora Library for Ultibo using RFM9x Modules

Should support all rfm9x modules, but only tested with rfm98

Still lots to implement, but can send basic packets between two rfm98 modules

Partially ported from Arduino library written by Sandeep Mistry - https://github.com/sandeepmistry/arduino-LoRa

Default Settings: (and only settings since there is no functions yet to set this differently)
 - spreading factor 7
 - signal bandwidth 125E3Hz
 - coding rate 5
 - preamble length 8
 - sync word 0x12
 - no crc

 lora unit connected to spi0

# todo
1. lots! 