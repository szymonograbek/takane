//! Open Movies: a built-in add-on with Creative Commons and public domain films that play
//! straight away.
//!
//! A fresh signed-out profile lists it first, so the first row of the board and the first
//! streams a signed-out user finds are films anyone may watch. The Creative Commons films are
//! the Blender Foundation's; the public domain ones are copies on the Internet Archive.
//!
//! It answers here, in the bridge: its URL is under the reserved `.invalid` domain, so none of
//! its requests reach the network. Titles, artwork and details come from Cinemeta by IMDb id,
//! like any other movie's.

use serde_json::{json, Value};
use stremio_core::types::addon::Descriptor;
use stremio_core::types::profile::Profile;

use crate::fetch::FetchOutcome;

const BASE_URL: &str = "https://open-movies.invalid";
const CATALOG_ID: &str = "open-movies";

struct Film {
    imdb_id: &'static str,
    name: &'static str,
    year: &'static str,
    quality: &'static str,
    license: &'static str,
    /// Who made the film, or for a public domain one, who hosts the copy.
    credit: &'static str,
    url: &'static str,
}

/// Most recognizable first: the first is the board's hero.
const FILMS: &[Film] = &[
    Film {
        imdb_id: "tt1727587",
        name: "Sintel",
        year: "2010",
        quality: "1080p",
        license: "CC BY 3.0",
        credit: "Blender Foundation",
        url: "https://download.blender.org/durian/movies/Sintel.2010.1080p.mkv",
    },
    Film {
        imdb_id: "tt0063350",
        name: "Night of the Living Dead",
        year: "1968",
        quality: "1080p",
        license: "Public domain",
        credit: "Internet Archive",
        url: "https://archive.org/download/Night.Of.The.Living.Dead_1080p/NightOfTheLivingDead_PS3.mp4",
    },
    Film {
        imdb_id: "tt0056923",
        name: "Charade",
        year: "1963",
        quality: "720p",
        license: "Public domain",
        credit: "Internet Archive",
        url: "https://archive.org/download/charade-1963-cary-grant-audrey-hepburn-comedy-mystery-romance-thriller-full-movie/Charade_READY.mp4",
    },
    Film {
        imdb_id: "tt0032599",
        name: "His Girl Friday",
        year: "1940",
        quality: "SD",
        license: "Public domain",
        credit: "Internet Archive",
        url: "https://archive.org/download/his_girl_friday/his_girl_friday.mp4",
    },
    Film {
        imdb_id: "tt0013442",
        name: "Nosferatu",
        year: "1922",
        quality: "SD",
        license: "Public domain",
        credit: "Internet Archive",
        url: "https://archive.org/download/Nosferatu1922/Nosferatu.mp4",
    },
    Film {
        imdb_id: "tt2285752",
        name: "Tears of Steel",
        year: "2012",
        quality: "720p",
        license: "CC BY 3.0",
        credit: "Blender Foundation",
        url: "https://download.blender.org/demo/movies/ToS/tears_of_steel_720p.mov",
    },
    Film {
        imdb_id: "tt0039566",
        name: "Life with Father",
        year: "1947",
        quality: "SD",
        license: "Public domain",
        credit: "Internet Archive",
        url: "https://archive.org/download/LifeWithFather/LifeWithFather.mp4",
    },
    Film {
        imdb_id: "tt0052077",
        name: "Plan 9 from Outer Space",
        year: "1957",
        quality: "720p",
        license: "Public domain",
        credit: "Internet Archive",
        url: "https://archive.org/download/plan-9-from-outer-space_202009/Plan%209%20from%20Outer%20Space.mp4",
    },
    Film {
        imdb_id: "tt1254207",
        name: "Big Buck Bunny",
        year: "2008",
        quality: "1080p",
        license: "CC BY 3.0",
        credit: "Blender Foundation",
        url: "https://archive.org/download/BigBuckBunnyFULLHD60FPS/Big%20Buck%20Bunny%20-%20FULL%20HD%2060FPS.mp4",
    },
    Film {
        imdb_id: "tt0051744",
        name: "House on Haunted Hill",
        year: "1959",
        quality: "SD",
        license: "Public domain",
        credit: "Internet Archive",
        url: "https://archive.org/download/The_House_On_Haunted_Hill/The_House_On_Haunted_Hill.mp4",
    },
    Film {
        imdb_id: "tt0015324",
        name: "Sherlock Jr.",
        year: "1924",
        quality: "720p",
        license: "Public domain",
        credit: "Internet Archive",
        url: "https://archive.org/download/sherlockjr1924_201909/Sherlock%20Jr.%20-%20Buster%20Keaton%20%281924%29%20HD%20%5B720p%5D.mp4",
    },
    Film {
        imdb_id: "tt0045162",
        name: "The Snows of Kilimanjaro",
        year: "1952",
        quality: "SD",
        license: "Public domain",
        credit: "Internet Archive",
        url: "https://archive.org/download/Kilimanjaro/The_Snows_of_Kilimanjaro.mp4",
    },
    Film {
        imdb_id: "tt4957236",
        name: "Cosmos Laundromat",
        year: "2015",
        quality: "1080p",
        license: "CC BY 4.0",
        credit: "Blender Foundation",
        url: "https://archive.org/download/CosmosLaundromatFirstCycle/Cosmos%20Laundromat%20-%20First%20Cycle%20%281080p%29.mp4",
    },
    Film {
        imdb_id: "tt0054033",
        name: "The Little Shop of Horrors",
        year: "1960",
        quality: "SD",
        license: "Public domain",
        credit: "Internet Archive",
        url: "https://archive.org/download/TheLittleShopOfHorrors1960_765/TheLittleShopOfHorrors1960.mp4",
    },
    Film {
        imdb_id: "tt0046414",
        name: "Beat the Devil",
        year: "1953",
        quality: "720p",
        license: "Public domain",
        credit: "Internet Archive",
        url: "https://archive.org/download/beat-the-devil-1953_202406/Beat%20The%20Devil%201953.mp4",
    },
    Film {
        imdb_id: "tt0058700",
        name: "The Last Man on Earth",
        year: "1964",
        quality: "720p",
        license: "Public domain",
        credit: "Internet Archive",
        url: "https://archive.org/download/TheLastManOnEarthHD/The%20Last%20Man%20on%20Earth%20HD.mp4",
    },
    Film {
        imdb_id: "tt15804252",
        name: "Sprite Fright",
        year: "2021",
        quality: "1080p",
        license: "CC BY 4.0",
        credit: "Blender Foundation",
        url: "https://archive.org/download/sprite-fright/Sprite%20Fright%20-%20Open%20Movie%20by%20Blender%20Studio-804p.mp4",
    },
    Film {
        imdb_id: "tt0033891",
        name: "Meet John Doe",
        year: "1941",
        quality: "SD",
        license: "Public domain",
        credit: "Internet Archive",
        url: "https://archive.org/download/meet_john_doe/meet_john_doe.mp4",
    },
    Film {
        imdb_id: "tt0028010",
        name: "My Man Godfrey",
        year: "1936",
        quality: "SD",
        license: "Public domain",
        credit: "Internet Archive",
        url: "https://archive.org/download/MyManGodfrey1936/MyManGodfrey1936.mp4",
    },
    Film {
        imdb_id: "tt0055830",
        name: "Carnival of Souls",
        year: "1962",
        quality: "SD",
        license: "Public domain",
        credit: "Internet Archive",
        url: "https://archive.org/download/CarnivalofSouls/CarnivalOfSouls.mp4",
    },
    Film {
        imdb_id: "tt0038991",
        name: "The Stranger",
        year: "1946",
        quality: "SD",
        license: "Public domain",
        credit: "Internet Archive",
        url: "https://archive.org/download/TheStranger_0/The_Stranger.mp4",
    },
    Film {
        imdb_id: "tt0037638",
        name: "Detour",
        year: "1945",
        quality: "SD",
        license: "Public domain",
        credit: "Internet Archive",
        url: "https://archive.org/download/Detour/Detour.mp4",
    },
    Film {
        imdb_id: "tt0807840",
        name: "Elephants Dream",
        year: "2006",
        quality: "SD",
        license: "CC BY 2.5",
        credit: "Blender Foundation",
        url: "https://download.blender.org/ED/elephantsdream-720-h264-st-aac.mov",
    },
    Film {
        imdb_id: "tt0042369",
        name: "D.O.A.",
        year: "1950",
        quality: "SD",
        license: "Public domain",
        credit: "Internet Archive",
        url: "https://archive.org/download/D.o.a.VideoQualityUpgrade/D.o.a.VideoQualityUpgrade.mp4",
    },
    Film {
        imdb_id: "tt0038057",
        name: "Scarlet Street",
        year: "1945",
        quality: "SD",
        license: "Public domain",
        credit: "Internet Archive",
        url: "https://archive.org/download/ScarletStreetVideoQualityUpgrade/ScarletStreetVideoQualityUpgrade.mp4",
    },
    Film {
        imdb_id: "tt0029606",
        name: "A Star Is Born",
        year: "1937",
        quality: "720p",
        license: "Public domain",
        credit: "Internet Archive",
        url: "https://archive.org/download/AStarIsBorn1937FullHDMovie/AStarIsBorn%281937%29FullHDMovie.mp4",
    },
    Film {
        imdb_id: "tt0057298",
        name: "McLintock!",
        year: "1963",
        quality: "SD",
        license: "Public domain",
        credit: "Internet Archive",
        url: "https://archive.org/download/Mclintock.avi/Mclintock.mp4",
    },
    Film {
        imdb_id: "tt0031397",
        name: "Gulliver's Travels",
        year: "1939",
        quality: "SD",
        license: "Public domain",
        credit: "Internet Archive",
        url: "https://archive.org/download/gullivers_travels1939/gullivers_travels1939.mp4",
    },
    Film {
        imdb_id: "tt6914802",
        name: "Agent 327: Operation Barbershop",
        year: "2017",
        quality: "1080p",
        license: "CC BY-ND 4.0",
        credit: "Blender Foundation",
        url: "https://archive.org/download/agent327operationbarbershop/agent327-1080.mp4",
    },
    Film {
        imdb_id: "tt0015648",
        name: "Battleship Potemkin",
        year: "1925",
        quality: "SD",
        license: "Public domain",
        credit: "Internet Archive",
        url: "https://archive.org/download/PhantasmagoriaTheater-BattleshipPotemkin1925396/PhantasmagoriaTheater-BattleshipPotemkin1925396.mp4",
    },
    Film {
        imdb_id: "tt0045877",
        name: "The Hitch-Hiker",
        year: "1953",
        quality: "SD",
        license: "Public domain",
        credit: "Internet Archive",
        url: "https://archive.org/download/Hitch_Hiker/Hitch-Hiker.mp4",
    },
    Film {
        imdb_id: "tt0044789",
        name: "Kansas City Confidential",
        year: "1952",
        quality: "SD",
        license: "Public domain",
        credit: "Internet Archive",
        url: "https://archive.org/download/Kansas_City_Confidential_1952/Kansas_City_Confidential.mp4",
    },
    Film {
        imdb_id: "tt0047542",
        name: "Suddenly",
        year: "1954",
        quality: "SD",
        license: "Public domain",
        credit: "Internet Archive",
        url: "https://archive.org/download/suddenly/suddenly.mp4",
    },
    Film {
        imdb_id: "tt0034012",
        name: "Penny Serenade",
        year: "1941",
        quality: "SD",
        license: "Public domain",
        credit: "Internet Archive",
        url: "https://archive.org/download/penny_serenade/penny_serenade.mp4",
    },
    Film {
        imdb_id: "tt0043983",
        name: "Royal Wedding",
        year: "1951",
        quality: "SD",
        license: "Public domain",
        credit: "Internet Archive",
        url: "https://archive.org/download/royal_wedding/royal_wedding.mp4",
    },
    Film {
        imdb_id: "tt0029322",
        name: "Nothing Sacred",
        year: "1937",
        quality: "SD",
        license: "Public domain",
        credit: "Internet Archive",
        url: "https://archive.org/download/NothingSacredVideoQualityUpgrade/NothingSacredVideoQualityUpgrade.mp4",
    },
    Film {
        imdb_id: "tt0039152",
        name: "Angel and the Badman",
        year: "1947",
        quality: "SD",
        license: "Public domain",
        credit: "Internet Archive",
        url: "https://archive.org/download/angel_and_the_badman/angel_and_the_badman.mp4",
    },
    Film {
        imdb_id: "tt0038494",
        name: "Dressed to Kill",
        year: "1946",
        quality: "SD",
        license: "Public domain",
        credit: "Internet Archive",
        url: "https://archive.org/download/DressedToKill1946/DressedToKill.mp4",
    },
    Film {
        imdb_id: "tt0038259",
        name: "The Woman in Green",
        year: "1945",
        quality: "SD",
        license: "Public domain",
        credit: "Internet Archive",
        url: "https://archive.org/download/TheWomanInGreen1945/TheWomanInGreen.mp4",
    },
    Film {
        imdb_id: "tt0000417",
        name: "A Trip to the Moon",
        year: "1902",
        quality: "SD",
        license: "Public domain",
        credit: "Internet Archive",
        url: "https://archive.org/download/ATripToTheMoon20Fps/TripToTheMoon20Fps.mp4",
    },
];

/// The profile a signed-out user starts with: core's default add-ons after Open Movies.
pub fn anonymous_profile() -> Profile {
    let mut profile = Profile::default();
    profile.addons.insert(0, descriptor());
    profile
}

/// The answer to `url` when it is one of Open Movies' requests, or `None` for any other URL.
pub fn respond(url: &str) -> Option<FetchOutcome> {
    let path = url.strip_prefix(BASE_URL)?;
    let body = if path == "/manifest.json" {
        Some(manifest())
    } else if path == format!("/catalog/movie/{CATALOG_ID}.json") {
        Some(json!({ "metas": FILMS.iter().map(meta_preview).collect::<Vec<_>>() }))
    } else {
        path.strip_prefix("/stream/movie/")
            .and_then(|file| file.strip_suffix(".json"))
            .map(|imdb_id| json!({ "streams": FILMS.iter().filter(|film| film.imdb_id == imdb_id).map(stream).collect::<Vec<_>>() }))
    };
    Some(match body {
        Some(body) => FetchOutcome::Response { status: 200, body: body.to_string().into_bytes() },
        None => FetchOutcome::Response { status: 404, body: vec![] },
    })
}

fn descriptor() -> Descriptor {
    serde_json::from_value(json!({
        "transportUrl": format!("{BASE_URL}/manifest.json"),
        "manifest": manifest(),
    }))
    .expect("the Open Movies descriptor parses")
}

fn manifest() -> Value {
    json!({
        "id": "app.takane.open-movies",
        "version": "1.0.0",
        "name": "Open Movies",
        "description": "Creative Commons films by the Blender Foundation and public domain classics from the Internet Archive.",
        "types": ["movie"],
        "resources": ["catalog", "stream"],
        // Full ids as prefixes, so core asks for streams of these films only.
        "idPrefixes": FILMS.iter().map(|film| film.imdb_id).collect::<Vec<_>>(),
        "catalogs": [{ "type": "movie", "id": CATALOG_ID, "name": "Free" }],
    })
}

fn meta_preview(film: &Film) -> Value {
    let image = |kind: &str| format!("https://images.metahub.space/{kind}/medium/{}/img", film.imdb_id);
    json!({
        "id": film.imdb_id,
        "type": "movie",
        "name": film.name,
        "releaseInfo": film.year,
        "poster": image("poster"),
        "background": image("background"),
        "logo": image("logo"),
    })
}

fn stream(film: &Film) -> Value {
    json!({
        "url": film.url,
        "name": "Open Movies",
        "description": format!("{} · {} · {}", film.quality, film.license, film.credit),
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use stremio_core::types::addon::Manifest;
    use stremio_core::types::resource::{MetaItemPreview, Stream};

    fn body(url: &str) -> Vec<u8> {
        match respond(url) {
            Some(FetchOutcome::Response { status: 200, body }) => body,
            other => panic!("{url}: {other:?}"),
        }
    }

    #[test]
    fn anonymous_profile_lists_open_movies_first() {
        let profile = anonymous_profile();
        assert_eq!(profile.addons[0].transport_url.as_str(), "https://open-movies.invalid/manifest.json");
        assert_eq!(profile.addons.len(), Profile::default().addons.len() + 1);
    }

    #[test]
    fn answers_its_manifest_catalog_and_streams() {
        let manifest: Manifest = serde_json::from_slice(&body("https://open-movies.invalid/manifest.json")).unwrap();
        assert_eq!(manifest.name, "Open Movies");

        #[derive(serde::Deserialize)]
        struct Metas {
            metas: Vec<MetaItemPreview>,
        }
        let catalog: Metas = serde_json::from_slice(&body("https://open-movies.invalid/catalog/movie/open-movies.json")).unwrap();
        assert_eq!(catalog.metas.len(), FILMS.len());

        #[derive(serde::Deserialize)]
        struct Streams {
            streams: Vec<Stream>,
        }
        let streams: Streams = serde_json::from_slice(&body("https://open-movies.invalid/stream/movie/tt1727587.json")).unwrap();
        assert_eq!(streams.streams.len(), 1);
    }

    #[test]
    fn leaves_other_urls_to_the_host() {
        assert!(respond("https://v3-cinemeta.strem.io/manifest.json").is_none());
        assert!(matches!(
            respond("https://open-movies.invalid/meta/movie/tt1727587.json"),
            Some(FetchOutcome::Response { status: 404, .. })
        ));
    }
}
