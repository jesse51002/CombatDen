"""Member service — currently returns mocked data."""

from datetime import UTC, datetime, timedelta
from uuid import UUID

from src.members.members_schemas import (
    DiscountInfo,
    LinkedAccount,
    MemberDetailResponse,
    MembershipInfo,
    PaymentRecord,
    PersonalInfo,
    RankRetention,
    RewardCard,
)

MOCK_CRM_USER_ID = UUID("a1b2c3d4-e5f6-7890-abcd-ef1234567890")
MOCK_GYM_ID = UUID("11111111-2222-3333-4444-555555555555")
MOCK_WIFE_ID = UUID("b2c3d4e5-f6a7-8901-bcde-f12345678901")
MOCK_DAUGHTER_ID = UUID("c3d4e5f6-a7b8-9012-cdef-123456789012")
MOCK_SON_ID = UUID("d4e5f6a7-b8c9-0123-defa-234567890123")
MOCK_PLAN_ID = UUID("e5f6a7b8-c9d0-1234-efab-345678901234")
MOCK_DISCOUNT_ID = UUID("f6a7b8c9-d0e1-2345-fabc-456789012345")

NOW = datetime.now(UTC)


class MemberService:
    """Service for member detail operations.

    Currently returns mocked static data. Replace with real
    repository calls when the data layer is implemented.
    """

    async def get_member_detail(
        self,
        crm_user_id: UUID,
    ) -> MemberDetailResponse:
        """Return full member detail for the Specific Member screen.

        Args:
            gym_id: The gym this member belongs to.

        Returns:
            MemberDetailResponse with all screen sections populated.
        """
        return MemberDetailResponse(
            crm_user_id=MOCK_CRM_USER_ID,
            first_name="Justin",
            last_name="Stemmons",
            photo_url="https://placehold.co/120x120",
            account_status="active",
            personal_info=PersonalInfo(
                phone="(555) 123-4567",
                email="justin.stemmons@email.com",
                address="123 Main St, Austin, TX 78701",
                emergency_contact_name="Sarah Stemmons",
                emergency_contact_phone="(555) 987-6543",
                emergency_contact_email="sarah.stemmons@email.com",
            ),
            membership=MembershipInfo(
                plan_name="Unlimited Classes Membership",
                plan_type="Family",
                status="active",
                base_cost=165.00,
                billing_cycle="monthly",
                total_cost=320.00,
                cost_formula="($165.00 + $80 * 3) * 20% off = $320",
                last_paid_date=NOW - timedelta(days=5),
                next_due_date=NOW + timedelta(days=25),
                start_date=NOW - timedelta(days=365),
                linked_accounts=[
                    LinkedAccount(
                        crm_user_id=MOCK_WIFE_ID,
                        first_name="Sarah",
                        last_name="Stemmons",
                        photo_url="https://placehold.co/36x36",
                    ),
                    LinkedAccount(
                        crm_user_id=MOCK_DAUGHTER_ID,
                        first_name="Emma",
                        last_name="Stemmons",
                        photo_url="https://placehold.co/36x36",
                    ),
                    LinkedAccount(
                        crm_user_id=MOCK_SON_ID,
                        first_name="Jake",
                        last_name="Stemmons",
                        photo_url="https://placehold.co/36x36",
                    ),
                ],
                discounts=[
                    DiscountInfo(
                        discount_id=MOCK_DISCOUNT_ID,
                        discount_name="Winter Discount",
                        percentage_off=20.0,
                        start_date=datetime(2025, 11, 1, tzinfo=UTC),
                        end_date=datetime(2026, 1, 1, tzinfo=UTC),
                    ),
                ],
            ),
            rank_retention=RankRetention(
                current_rank=2,
                rank_name="Silver (Amateur)",
                classes_in_rank=10,
                estimated_classes_for_rank=100,
                recommend_promo_in=5,
                last_class=NOW - timedelta(days=5),
                class_streak_weeks=5,
                points_balance=3400,
                videos_watched=14,
            ),
            recently_redeemed_rewards=[
                RewardCard(
                    reward_id=UUID("11112222-3333-4444-5555-666677778888"),
                    title="Free T-Shirt",
                    subtitle="Redeemed 2 weeks ago",
                    image_url="https://placehold.co/100x100",
                    point_cost=500,
                ),
                RewardCard(
                    reward_id=UUID("22223333-4444-5555-6666-777788889999"),
                    title="Private Session",
                    subtitle="Redeemed 1 month ago",
                    image_url="https://placehold.co/100x100",
                    point_cost=1500,
                ),
                RewardCard(
                    reward_id=UUID("33334444-5555-6666-7777-888899990000"),
                    title="Protein Shake",
                    subtitle="Redeemed 2 months ago",
                    image_url="https://placehold.co/100x100",
                    point_cost=200,
                ),
            ],
            payment_history=[
                PaymentRecord(
                    transaction_id=UUID("aaaa1111-bbbb-cccc-dddd-eeee11112222"),
                    item_type="membership",
                    amount_paid=320.00,
                    time=NOW - timedelta(days=5),
                ),
                PaymentRecord(
                    transaction_id=UUID("aaaa2222-bbbb-cccc-dddd-eeee22223333"),
                    item_type="membership",
                    amount_paid=320.00,
                    time=NOW - timedelta(days=35),
                ),
                PaymentRecord(
                    transaction_id=UUID("aaaa3333-bbbb-cccc-dddd-eeee33334444"),
                    item_type="membership",
                    amount_paid=320.00,
                    time=NOW - timedelta(days=65),
                ),
                PaymentRecord(
                    transaction_id=UUID("aaaa4444-bbbb-cccc-dddd-eeee44445555"),
                    item_type="membership",
                    amount_paid=320.00,
                    time=NOW - timedelta(days=95),
                ),
                PaymentRecord(
                    transaction_id=UUID("aaaa5555-bbbb-cccc-dddd-eeee55556666"),
                    item_type="membership",
                    amount_paid=320.00,
                    time=NOW - timedelta(days=125),
                ),
            ],
        )
