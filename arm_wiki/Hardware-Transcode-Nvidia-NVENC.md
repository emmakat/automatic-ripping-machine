# Installing NVIDIA drivers:
We recommended to do a driver update immediately after installing ubuntu. In software updater, check the settings, other software tab and ensure the driver for your gpu is installed. Select the proprietary, tested option.

## Checking for NVENC support
Nvidia NVENC support comes with HandBrake in some distros, to check first make sure you have at least
- GeForce GTX Pascal (1050+)
- RTX Turing (1650+, 2060+) 
- or later GPU.
- drivers are updated to at least 418.81 or later.

Testing if HandBrake recognizes your GPU - Run

`HandBrakeCLI --help | grep -A12 "Select video encoder"` 
or 
`HandBrakeCLI --help > /tmp/HandBrakeHelp && grep -A12 "Select video encoder" /tmp/HandBrakeHelp`

into your ssh/terminal window

If NVENC is enabled should give something similar to
```
   -e, --encoder <string>  Select video encoder:
                               x264
                               x264_10bit
                               nvenc_h264
                               x265
                               x265_10bit
                               x265_12bit
                               nvenc_h265
                               nvenc_h265_10bit
                               mpeg4
                               mpeg2
                               VP8
                               VP9
HandBrake has exited.
```
You can also check with 
`HandBrakeCLI --version` and it should output

```
[23:37:19] Compile-time hardening features are enabled
[23:37:19] nvenc: version 12.0 is available
[23:37:19] nvdec: is not compiled into this build
[23:37:19] hb_init: starting libhb thread
[23:37:19] thread 7f002300e700 started ("libhb")
HandBrake 20230130172537-a5238f484-master
```

## Cant see those options ?

If you don't see the extra options for nvenc then you will need to build HandBrakeCLI from source.
Here is an [installation script](https://github.com/emmakat/automatic-ripping-machine/blob/emmakat-NVENC-handbrake-setup/scripts/installers/NVENC_handbrake_setup.sh)


## Post install
#### 1. Reload systemd
```
sudo systemctl daemon-reload
```
#### 2. Restart Docker daemon 
```
sudo systemctl restart docker
```

#### 3. Verify Docker NVIDIA integration works
```
docker run --rm --gpus all nvidia/cuda:12.0-base-ubuntu20.04 nvidia-smi
```
#### The script adds the arm user to the video & render groups so that arm can access the NVENC encoder
```
sudo usermod -a -G video arm 
sudo usermod -a -G render arm
```

### Once handbrake recognizes your GPU, you can use one of the 2 built in profiles in your arm.yaml config.

`H.265 NVENC 2160p 4K` OR `H.265 NVENC 1080p`



------
## 🐋 - NVENC doesn't work

Be sure that both variables for `NVIDIA_DRIVER_CAPABILITIES=all`
and `--gpus all` are set as NVENC won't work without them

## HandBrake Official Documentation 
For more detailed information you can read through the official HandBrake documentation [HandBrake Building for linux](https://handbrake.fr/docs/en/1.3.0/developer/build-linux.html)

