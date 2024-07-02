# Edge Qauto

## Pre-requisites

Install Java following the React Native guide: https://reactnative.dev/docs/set-up-your-environment?platform=android

Install [Maestro](https://maestro.mobile.dev/getting-started/installing-maestro) and [Flashlight](https://docs.flashlight.dev/) to be able to run the test scripts. 

## Usage

### Install

Clone this repository and change into the directory:

```sh
git clone git@github.com:EdgeApp/edge-qauto.git
cd edge-qauto
```

### Setup

Run the setup script:

```sh
source qauto
```

This will prompt you with questions about which test you wish to run. 
You can run this command anytime to change the choices you made.

### Run

Run the test configured by the previous with the command:

```sh
qauto
```

This will run the test and ask you if you want to show the result report.

The default number of tests (iterations) is 8, but you can change this by passing
a number to the `qauto` command:

```sh
qauto 3
```

### Re-opening Results

The results are saved to the `results/` directory as a JSON file. You can always
open the results again using:

```sh
flashlight report results/<filename>.json
```


## Pronunciation

Qauto is pronounced "Kado".
