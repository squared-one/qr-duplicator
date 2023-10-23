#!/bin/bash

# Install Barcode Duplicator
sudo rm /etc/systemd/system/barcode_duplicator.service 
sudo cp barcode_duplicator.service /etc/systemd/system/barcode_duplicator.service
sudo systemctl daemon-reload
sudo systemctl enable barcode_duplicator.service
sudo systemctl start barcode_duplicator.service
sudo systemctl status barcode_duplicator.service