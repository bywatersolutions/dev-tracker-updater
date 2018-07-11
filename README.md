# Tracker Updater - Update values in one Bugzilla repo from another!

## How to install and configure

* Clone the repository: `https://github.com/bywatersolutions/dev-tracker-updater.git`
* Symlink the shell script to some place in your executable path: `ln -s /path/to/dev-tracker-updater/bin/tracker-updater /usr/local/bin/.`
* Copy the example env file to your home directory: `cp .tracker-updater.env.example ~/.`
* Edit that file, change the example values to your values: `vi ~/.tracker-updater.env.example`
* Try running the command `tracker-updater --help` to see how to use the app
