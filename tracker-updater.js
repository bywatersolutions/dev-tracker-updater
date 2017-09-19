#!/usr/bin/env node

let bz = require("bz");
let colors = require("colors/safe");
let options = require("node-getopt-long").options(
  [
    ["bws_url|bws-url=s", "BWS tracker URL"],
    ["bws_username|bws-username=s", "BWS tracker username"],
    ["bws_password|bws-password=s", "BWS tracker password"],
    ["community_url|community-url=s", "Community tracker URL"],
    ["community_username|community-username=s", "Community tracker username"],
    ["community_password|community-password=s", "Community tracker password"]
  ],
  {
    name: "tracker-updater",
    commandVersion: 1.0,
    defaults: {
      bws_url: "http://tracker.devs.bywatersolutions.com/rest/",
      community_url: "https://bugs.koha-community.org/bugzilla3/rest/"
    }
  }
);

let bws_tracker = bz.createClient({
  url: options.bws_url,
  username: options.bws_username,
  password: options.bws_password,
  timeout: 30000
});

let community_tracker = bz.createClient({
  url: options.community_url,
  username: options.community_username,
  password: options.community_password,
  timeout: 30000
});

let searchParams = { status: "Submitted to Community" };
bws_tracker.searchBugs(searchParams, function(error, bugs) {
  if (error) {
    console.log(colors.red("ERROR SEARCHING BWS DEV TRACKER!"));
    console.log(error);
    process.exit(1);
  }

  for (let i = 0; i < bugs.length; i++) {
    let bws_bug = bugs[i];
    let bws_status = bws_bug.cf_community_status;

    community_tracker.getBug(bws_bug.cf_community_bug, function(
      error,
      community_bug
    ) {
      if (error) {
        console.log("BWS ID: " + colors.red(bws_bug.id));
        console.log(colors.red("ERROR GETTING COMMUNITY BUG!"));
        console.log(error);
        return;
      }

      let community_status = community_bug.status;
      console.log("BWS ID: " + colors.green(bws_bug.id));
      console.log("BWS STATUS: " + colors.green(bws_status));
      console.log("STATUS: " + colors.cyan(community_status));

      if (bws_status != community_status) {
        bws_tracker.updateBug(
          bws_bug.id,
          { cf_community_status: community_status },
          function(error, ok) {
            console.log(
              `Updating BWS Tracker Bug ${colors.green(
                bws_bug.id
              )} with status ${colors.green(
                bws_status
              )} to community status ${colors.cyan(
                community_status
              )} from community bug ${colors.cyan(community_bug.id)}`
            );
            if (error) {
              console.log(colors.red("ERROR UPDATING BWS TRACKER!"));
              console.log(error);
            }
          }
        );
      }
    });
  }
});
