from copy import deepcopy

CONFIG = {'source_timezone': 'Europe/Warsaw', 'source_currencies': {
    'pms_reservations': 'PLN', 'cm_channels': 'PLN', 'fin_budgets_costs': 'PLN'}}

def snapshot():
    return deepcopy({
        'pms_hotels': [dict(hotel_id='H1', hotel_name=' Hotel Test ', city='Kraków', region='małopolskie')],
        'pms_guests': [dict(guest_id='G1', first_name='Test', last_name='Gość', email='', phone=None)],
        'pms_rooms': [dict(room_id='R1', hotel_id='H1', room_number='001', room_type='Standard')],
        'pms_reservations': [dict(reservation_id='B1', hotel_id='H1', guest_id='G1', room_id='R1',
                                  guest_segment='Leisure', booking_date='2026-11-01', check_in_date='17.11.2026',
                                  check_out_date='2026/11/20', status='Zakończona', room_revenue='1 234,50',
                                  cancellation_fee='0.00', updated_at='2026-11-02 12:00:00')],
        'pms_stays': [dict(stay_id='S1', reservation_id='B1', guest_id='G1', room_id='R1',
                          actual_check_in='17/11/2026', actual_check_out='2026-11-20')],
        'cm_channels': [dict(reservation_id='B1', channel_code='DIRECT', commission_rate='0.00', commission_amount='0')],
        'fin_budgets_costs': [dict(hotel_id='H1', month_id='11.2026', cost_category='Energy', budget_amount='2,000.00', actual_cost='1.500,00')],
    })
