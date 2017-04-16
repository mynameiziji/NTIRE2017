# NTIRE2017

## Introduction
This repository is implemented for [NTIRE2017 Challenge](http://www.vision.ee.ethz.ch/ntire17/), based on [Facebook ResNet](https://github.com/facebook/fb.resnet.torch) and [SR ResNet](https://arxiv.org/pdf/1609.04802.pdf)

By [SNU-CVLAB](http://cv.snu.ac.kr/?page_id=57) Members; Seungjun Nah, Lim Beem Heewon Kim, Sanghyun Son

## Challenge Results
Statistics | Individual Models| MultiScale Model| Leaderboard No.(IM/MSM) 
-- | -- | -- | --
Bicubic X2 |  |  | 
Bicubic X3 |  |  | 
Bicubic X4 |  |  | 
Unknown X2 |  |  | 
Unknown X3 |  |  | 
Unknown X4 |  |  | 

## Dependencies
* torch7
* cudnn
* nccl (Optional, for faster GPU communication)

## Code
1. Clone this repository into $makeReposit:
   ```bash
   makeReposit = /home/LBNet/
   mkdir -p $makeReposit/; cd $makeReposit/
   git clone https://github.com/LimBee/NTIRE2017.git
   ```

## Dataset
1. Please download the dataset from below.
   * DIV2K produced by NTIRE2017
       ```bash
       makeData = /var/tmp/dataset/ # set absolute path as desired
       mkdir -p $makeData/; cd $makedata/
       wget https://cv.snu.ac.kr/~/DIV2K.tar
       tar -xvf DIV2K.tar
       ```
   * Flickr2K collected by Flickr
       ```bash
       makeData = /var/tmp/dataset/ # set absolute path as desired
       mkdir -p $makeData/; cd $makedata/
       wget https://cv.snu.ac.kr/~/Flickr2K.tar
       tar -xvf Flickr2K.tar
       ```
2. Convert downloaded dataset into .t7 files (recommended)
   ```bash
   cd makeReposit/NTIRE2017/code/tools
   ```
   * To train DIV2K
       ```bash
       #This command generates multiple t7 files for
       #each images in DIV2K_train_HR folder
       th png_to_t7.lua -apath $makeData -dataset DIV2K -split true
       ```
       ```bash
       #This command generates a single t7 file that contains
       #every image in DIV2K_train_HR folder (Requires ~16GB RAM for training)
       th png_to_t7.lua -apath $makeData -dataset DIV2K -split false
       ```
   * To train Flickr2K
       ```bash
       #This command generates multiple t7 files for
       #each images in Flickr2K_HR folder
       th png_to_t7.lua -apath $makeData -dataset Flickr2K -split true
       ```

   * Or, you can use just .png files
## Quick Start(Demo)

1. Download Dataset into $makeData:


3. Download pre-trained Individual and MultiScale models:

   ```bash
   mkdir -p $makeReposit/NTIRE2017/demo/model/; cd $makeReposit/NTIRE2017/demo/model/
   wget https://cv.snu.ac.kr/~/bicubic_x2.t7 # Individual (bicubic_x3.t7 ~ unknown_x4.t7) 
   wget https://cv.snu.ac.kr/~/multiScale_model.t7
   ```

4. Run `test.lua` with a given model for selected validation image:

   ```bash
   cd $makeReposit/NTIRE2017/demo/
   # for individual bicubic x2
   th test.lua -type test -model bicubic_x2.t7 -degrade bicubic -scale 2 -nGPU 2 -selfEnsemble true -chopShave 10 -chopSize 16e4
   
   # for multiscale model
   th test.lua -type test -model multiscale.t7 -degrade bicubic -scale 2 -swap 1 -nGPU 2 -selfEnsemble true -chopShave 20 -chopSize 20e4 -dataDir ../../
   th test.lua -type test -model multiscale.t7 -degrade bicubic -scale 3 -swap 2 -nGPU 2 -selfEnsemble true -chopShave 20 -chopSize 24e4 -dataDir ../../
   th test.lua -type test -model multiscale.t7 -degrade bicubic -scale 4 -swap 3 -nGPU 2 -selfEnsemble true -chopShave 20 -chopSize 24e4 -dataDir ../../
   ```

## Training

1. To train default setting:

   ```bash
   th main.lua
   ```
   
2. To train fanal setting for individual bicubic x2:

   ```bash
   th main.lua -nFeat 256 -nResBlock 36 -patchSize 96 -scaleRes 0.1
   ```
3. To train fanal setting for multiScale model:

   ```bash
   th main.lua -nFeat 256 -nResBlock 36 -patchSize 96 -scaleRes 0.1
   ```
