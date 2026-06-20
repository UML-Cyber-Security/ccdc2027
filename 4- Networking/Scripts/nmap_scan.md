Before running the nmap_scan.sh make tsure to install the nmaptocsv in order to import to google sheets

`sudo apt install -y pipx`

`pipx install nmaptocsv`

`pipx ensurepath`

`nmaptocsv -x inventory_XXXXXXX_XXXX.xml -o inventory.csv`

`scp -P <port> user@public_ip:/home/user/nmap_inventory/inventory.csv .`

If you want one entire scan

```
sudo nmap -Pn -sS -sV --version-light \
  -p 22,53,80,443,445,3389 \
  -T4 --min-rate 1200 \
  10.0.1.0/24 10.0.2.0/24 10.0.3.0/24 \
  -oX inventory.xml
```