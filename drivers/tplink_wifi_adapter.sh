sudo apt update && sudo apt upgrade
sudo apt install linux-headers-$(uname -r) build-essential git
sudo openssl genrsa -out /var/lib/dkms/mok.key 2048
sudo openssl req -new -x509 -key /var/lib/dkms/mok.key -outform DER -out /var/lib/dkms/mok.pub -nodes -days 36500 -subj "/CN=DKMS Kernel Module Signing Key/"
sudo mokutil --import /var/lib/dkms/mok.pub # enter a password
mokutil --list-enrolled
cd /usr/src && sudo git clone https://github.com/lwfinger/rtw88.git rtw88-0.6
sudo dkms add -m rtw88 -v 0.6
sudo dkms build -m rtw88 -v 0.6
sudo dkms install -m rtw88 -v 0.6
dkms status

sudo dkms remove -m rtw88 -v 0.6 --all # Remove rtw88 from dkms
sudo rm -r /var/lib/dkms/rtw88 # Remove rtw88 dkms build files (if they exist)
sudo make -C /usr/src/rtw88-0.6 uninstall # Run uninstall target in Makefile
sudo rm -r /usr/src/rtw88-0.6 # Remove cloned source code directory

cd /home/$USER
git clone https://github.com/lwfinger/rtw88
cd rtw88
make
sudo make install
sudo make install_fw
reboot