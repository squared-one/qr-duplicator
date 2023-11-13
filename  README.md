# qr-duplicator
This thing takes input from a connected qrcode scanner ( todo: detect scanner event id automatically ) and creates a png qrcode which it then prints out on the connected Honeywell label printer.

Tiskárny https://prod-edam.honeywell.com/content/dam/honeywell-edam/sps/ppr/en-us/public/products/printers/desktop/pc42d/documents/sps-ppr-pc42d-sc-ug-en.pdf

http://localhost:631/admin/ 

Order deny,allow
Allow from @LOCAL

# list available printers
lpinfo -v

 # list available drivers
lpinfo -m

# check status
lpstat -l -p 

# set default printer
lpoptions -d Honeywell_3

# tisknout takhle
lp -d YourPrinterName ZPL.txt

# takhle pridat do cups tiskarnu s PPD driverem
lpadmin -p printername -E -v usb://Honeywell/PC42d-203-FP?serial=22235B54CB -m drv:///sample.drv/zebra.ppd 

4"x6" a tear-off

lp -o scaling=50 -o position=center filename.png


dependency imagemagick