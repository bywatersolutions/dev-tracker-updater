#!/usr/bin/env node

const async = require("async");
const bz = require("bz");
const colors = require("colors/safe");
const RT = require("bestpractical-rt");

const options = require("node-getopt-long").options(
  [
    ["rt_url|rt-url=s", "BWS RT URL"],
    ["rt_username|rt-username=s", "BWS RT username"],
    ["rt_password|rt-password=s", "BWS RT password"],
    ["dev_tracker_url|dev-url=s", "BWS tracker URL"],
    ["dev_tracker_username|dev-username=s", "BWS tracker username"],
    ["dev_tracker_password|dev-password=s", "BWS tracker password"],
    ["community_url|community-url=s", "Community tracker URL"],
    ["community_username|community-username=s", "Community tracker username"],
    ["community_password|community-password=s", "Community tracker password"],
    ["interactive|i", "Interactive mode"]
  ],
  {
    name: "tracker-updater",
    commandVersion: 1.0,
    defaults: {
      dev_tracker_url: "http://tracker.devs.bywatersolutions.com/rest/",
      community_url: "https://bugs.koha-community.org/bugzilla3/rest/"
    }
  }
);

const rt = new RT(options.rt_username, options.rt_password, options.rt_url);

const bws_tracker = bz.createClient({
  url: options.dev_tracker_url,
  username: options.dev_tracker_username,
  password: options.dev_tracker_password,
  timeout: 30000
});

const community_tracker = bz.createClient({
  url: options.community_url,
  username: options.community_username,
  password: options.community_password,
  timeout: 30000
});

process();

async function process() {
  await create_tracks();
  await create_community_bugs();
  await update_community_bugs();
}

function create_tracks() {
  return new Promise(function(resolve, reject) {
    const rt_query =
      "Queue = 'Development' AND CF.{Workflow} LIKE 'In Development' AND 'CF.{Work to be done}' IS NOT NULL AND 'CF.{Dev Tracker}' IS NULL";

    rt.search(rt_query, function(results) {
      console.log(
        colors.black.bgWhite("Checking RT for tickets that need Dev Tracks...")
      );

      Object.keys(results).forEach(async function(rt_ticket_id) {
        const val = results[rt_ticket_id];
        console.log(rt_ticket_id + " => " + val);

        // Wait a random number of seconds so we don't kill RT
        const min = 1;
        const max = 5;
        const rand = Math.floor(Math.random() * (max - min + 1) + min);
        await sleep(rand);

        rt.ticketProperties(rt_ticket_id, function(rt_ticket) {
          // These should never trigger because of the search limits we have already
          if (!rt_ticket["CF.{Work to be done}"]) return;
          if (rt_ticket["CF.{Dev Tracker}"]) return;

          const product = rt_ticket["CF.{Development Type}"] == "LibKi" // Mis-capitalized in RT
            ? "Libki"
            : "Koha";
          const component = rt_ticket["CF.{Development Type}"] == "Koha"
            ? "General"
            : rt_ticket["CF.{Development Type}"] == "LibKi" // Mis-capitalized in RT
              ? "General"
              : rt_ticket["CF.{Development Type}"];
          const version = rt_ticket["CF.{Development Type}"] == "LibKi" // Mis-capitalized in RT
            ? "Libki 2"
            : "unspecified";

          const track_data = {
            product: product,
            component: component,
            version: version,
            assigned_to: "jesse@bywatersolutions.com",
            summary: rt_ticket["Subject"],
            description: rt_ticket["CF.{Work to be done}"],
            op_sys: "All",
            rep_platform: "All",
            cf_rt_ticket: rt_ticket_id,
            bug_status: "In Development"
          };

          bws_tracker.createBug(track_data, function(error, track_id) {
            if (error) {
              console.log(
                colors.red("ERROR CREATING BUG REPORT ON DEV TRACKER!")
              );
              console.log(error);
              process.exit(1);
            }
            console.log("TRACK ID: " + track_id);

            // Update RT ticket with track id
            const properties = { "CF-Dev Tracker": track_id };
            rt.updateTicketProperties(rt_ticket_id, properties, function() {
              console.log("RT TICKET UPDATED");
            });
          });
        });
      });

      resolve();
    });
  });
}

function create_community_bugs() {
  return new Promise(function(resolve, reject) {
    let searchParams = {
      status: "In Development"
    };

    bws_tracker.searchBugs(searchParams, function(error, bugs) {
      console.log(
        colors.black.bgWhite(
          "Checking for Dev Tracks that need Community Bugs..."
        )
      );

      if (error) {
        console.log(colors.red("ERROR SEARCHING BWS DEV TRACKER!"));
        console.log(error);
        process.exit(1);
      }

      for (let i = 0; i < bugs.length; i++) {
        const bws_bug = bugs[i];

        // If there is already a community bug, we don't want to create a duplicate
        if (bws_bug.cf_community_bug) continue;

        // We don't want to mess with other projects
        if (bws_bug.product != "Koha") continue;

        // Plugins and XSLT mods don't get submitted to the community
        if (bws_bug.component != "General") continue;

        bws_tracker.bugComments(bws_bug.id, function(error, comments) {
          if (error) {
            console.log(
              colors.red("ERROR GETTING COMMENTS FROM COMMUNITY TRACKER!")
            );
            console.log(error);
            process.exit(1);
          }

          const comment = comments[0].text;

          const community_bug_data = {
            product: "Koha",
            component: "Architecture, internals, and plumbing",
            version: "master",
            assigned_to: bws_bug.assigned_to,
            summary: bws_bug.summary,
            description: comment
          };

          community_tracker.createBug(community_bug_data, function(
            error,
            community_bug_id
          ) {
            if (error) {
              console.log(
                colors.red("ERROR CREATING BUG REPORT ON COMMUNITY TRACKER!")
              );
              console.log(error);
              process.exit(1);
            }

            bws_tracker.updateBug(
              bws_bug.id,
              {
                cf_community_bug: community_bug_id
              },
              function(error, updated_bug) {
                if (error) {
                  console.log(
                    colors.red(
                      "ERROR ADDING NEW COMMUNITY BUG ID TO BWS DEV TRACKER!"
                    )
                  );
                  console.log(error);
                  process.exit(1);
                }

                console.log(
                  "Created community bug " +
                    colors.cyan(community_bug_id) +
                    " for tracker bug " +
                    colors.green(bws_bug.id)
                );
              }
            );
          });
        });
      }

      resolve();
    });
  });
}

function update_community_bugs() {
  return new Promise(function(resolve, reject) {
    searchParams = { status: "Submitted to Community" };
    bws_tracker.searchBugs(searchParams, function(error, bugs) {
      console.log(
        colors.black.bgWhite("Updating Dev Tracks from Community Bugs...")
      );

      if (error) {
        console.log(colors.red("ERROR SEARCHING BWS DEV TRACKER!"));
        console.log(error);
        process.exit(1);
      }

      for (let i = 0; i < bugs.length; i++) {
        let bws_bug = bugs[i];
        let bws_status = bws_bug.cf_community_status;

        // Set the community bug id to 0 to skip community processing
        if (bws_bug.cf_community_bug == "0") continue;

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
          let community_summary = community_bug.summary;

          console.log("BWS ID: " + colors.green(bws_bug.id));
          console.log("BWS STATUS: " + colors.green(bws_status));
          console.log("STATUS: " + colors.cyan(community_status));

          if (bws_status != community_status) {
            bws_tracker.updateBug(
              bws_bug.id,
              {
                cf_community_status: community_status,
                summary: community_summary
              },
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
    resolve();
  });
}

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms * 100));
}
