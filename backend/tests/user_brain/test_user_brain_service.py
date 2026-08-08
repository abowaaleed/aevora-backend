from app.user_brain import InMemoryUserBrainStore, UserBrainService


def test_user_brain_service_can_be_injected_with_custom_store():
    store = InMemoryUserBrainStore()
    service = UserBrainService(store=store)

    profile = service.get_or_create_profile("user-2")
    profile.display_name = "Mina"
    service.save_profile(profile)

    reloaded = service.get_or_create_profile("user-2")
    assert reloaded.display_name == "Mina"
