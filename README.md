git clone https://github.com/essent0/os-dev.git
cd os-dev
git submodule update --init
git clone --recurse-submodules
./buildall.sh
