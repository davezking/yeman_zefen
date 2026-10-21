import pytest

from yz.config import Config, ConfigError

BASE = {
    "API_BASE": "https://api.test/",
    "R2_ENDPOINT": "https://r2.test",
    "R2_ACCESS_KEY_ID": "k",
    "R2_SECRET_ACCESS_KEY": "s",
    "JOB_ID": "3",
}


def test_the_access_service_token_alone_is_enough():
    cfg = Config.from_env({**BASE, "CF_ACCESS_CLIENT_ID": "i", "CF_ACCESS_CLIENT_SECRET": "c"})
    assert (cfg.cf_access_client_id, cfg.cf_access_client_secret, cfg.ingest_token) == ("i", "c", "")


def test_the_ingest_token_alone_is_enough():
    cfg = Config.from_env({**BASE, "INGEST_TOKEN": " tok "})
    assert (cfg.cf_access_client_id, cfg.cf_access_client_secret, cfg.ingest_token) == ("", "", "tok")


@pytest.mark.parametrize("extra", [{}, {"CF_ACCESS_CLIENT_ID": "i"}, {"CF_ACCESS_CLIENT_SECRET": "c"}, {"INGEST_TOKEN": "  "}])
def test_without_credentials_it_names_both_ways(extra):
    with pytest.raises(ConfigError, match="INGEST_TOKEN, or CF_ACCESS_CLIENT_ID and CF_ACCESS_CLIENT_SECRET"):
        Config.from_env({**BASE, **extra})
