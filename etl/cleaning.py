"""US-02-02: deterministic, fail-closed staging transformation (no database I/O)."""
from collections import defaultdict
from datetime import date, datetime, timezone
from decimal import Decimal, InvalidOperation
import re
from zoneinfo import ZoneInfo

# table -> (business key, field -> (type, required))
def fields(required, optional=''):
    result = {}
    for names, needed in ((required, True), (optional, False)):
        for entry in names.split():
            name, _, kind = entry.partition(':')
            result[name] = (kind or 'text', needed)
    return result

SPECS = {
    'pms_hotels': (('hotel_id',), fields('hotel_id hotel_name', 'city region')),
    'pms_guests': (('guest_id',), fields('guest_id', 'first_name last_name email phone')),
    'pms_rooms': (('room_id',), fields('room_id hotel_id room_number room_type')),
    'pms_reservations': (('reservation_id',), fields(
        'reservation_id hotel_id guest_id room_id guest_segment booking_date:date '
        'check_in_date:date check_out_date:date status room_revenue:money '
        'cancellation_fee:money updated_at:timestamp currency:currency')),
    'pms_stays': (('stay_id',), fields(
        'stay_id reservation_id guest_id room_id actual_check_in:date', 'actual_check_out:date')),
    'cm_channels': (('reservation_id',), fields(
        'reservation_id channel_code commission_rate:rate commission_amount:money currency:currency')),
    'fin_budgets_costs': (('hotel_id', 'month_id', 'cost_category'), fields(
        'hotel_id month_id:month cost_category budget_amount:money actual_cost:money currency:currency')),
}
CURRENCIES = {'PLN': 'PLN', 'ZŁ': 'PLN', 'ZL': 'PLN', 'EUR': 'EUR', '€': 'EUR',
              'USD': 'USD', 'GBP': 'GBP', '£': 'GBP', 'CHF': 'CHF', 'CZK': 'CZK'}
STATUSES = {s.casefold(): s for s in ['Zakończona', 'Anulowana', 'No-Show', 'W trakcie', 'Oczekująca']}

class Invalid(ValueError):
    pass

def clean_text(value):
    if value is None:
        return None
    if isinstance(value, (dict, list, bool)):
        raise Invalid('INVALID_TEXT')
    return str(value).strip() or None

def parse_date(value):
    value = str(value).strip()
    matches = set()
    for fmt in ('%Y-%m-%d', '%d.%m.%Y', '%Y/%m/%d', '%d/%m/%Y'):
        try:
            matches.add(datetime.strptime(value, fmt).date())
        except ValueError:
            pass
    if len(matches) != 1:
        raise Invalid('INVALID_DATE')
    return matches.pop()

def parse_timestamp(value, source_timezone):
    try:
        dt = datetime.fromisoformat(str(value).strip().replace('Z', '+00:00'))
    except ValueError as exc:
        raise Invalid('INVALID_TIMESTAMP') from exc
    if dt.tzinfo is None:
        zone = ZoneInfo(source_timezone)
        candidates = set()
        for fold in (0, 1):
            utc = dt.replace(tzinfo=zone, fold=fold).astimezone(timezone.utc)
            if utc.astimezone(zone).replace(tzinfo=None) == dt:
                candidates.add(utc)
        if len(candidates) != 1:
            raise Invalid('AMBIGUOUS_OR_NONEXISTENT_LOCAL_TIME')
        return candidates.pop()
    return dt.astimezone(timezone.utc)

def parse_number(value, scale):
    s = str(value).strip().replace('\u00a0', ' ').replace('\u202f', ' ')
    # Decimal separator: dot or comma. Grouping only in complete groups of three.
    if re.fullmatch(r'[+-]?\d+(?:[.,]\d{1,' + str(scale) + r'})?', s):
        canonical = s.replace(',', '.')
    elif re.fullmatch(r'[+-]?\d{1,3}(?: \d{3})+(?:[.,]\d{1,' + str(scale) + r'})?', s):
        canonical = s.replace(' ', '').replace(',', '.')
    elif re.fullmatch(r'[+-]?\d{1,3}(?:\.\d{3})+,\d{1,' + str(scale) + r'}', s):
        canonical = s.replace('.', '').replace(',', '.')
    elif re.fullmatch(r'[+-]?\d{1,3}(?:,\d{3})+\.\d{1,' + str(scale) + r'}', s):
        canonical = s.replace(',', '')
    else:
        raise Invalid('INVALID_NUMBER_OR_PRECISION')
    try:
        number = Decimal(canonical)
        if not number.is_finite() or number < 0 or number >= Decimal('10000000000'):
            raise Invalid('NUMBER_OUT_OF_RANGE')
        return number.quantize(Decimal(1).scaleb(-scale))
    except InvalidOperation as exc:
        raise Invalid('INVALID_NUMBER_OR_PRECISION') from exc

def normalize(table, raw, source_currency=None, source_timezone='Europe/Warsaw'):
    result, errors = {}, []
    for name, (kind, required) in SPECS[table][1].items():
        value = raw.get(name)
        # Default is permitted ONLY for a source without a currency column.
        if name == 'currency' and name not in raw:
            value = source_currency
        try:
            value = clean_text(value)
            if value is None:
                if required:
                    raise Invalid('MISSING_REQUIRED')
            elif kind == 'date':
                value = parse_date(value)
            elif kind == 'timestamp':
                value = parse_timestamp(value, source_timezone)
            elif kind == 'month':
                if re.fullmatch(r'\d{4}-\d{2}', value):
                    value = parse_date(value + '-01')
                elif re.fullmatch(r'\d{2}[./]\d{4}', value):
                    value = parse_date('01.' + value.replace('/', '.'))
                else:
                    value = parse_date(value)
                    if value.day != 1:
                        raise Invalid('MONTH_MUST_START_ON_DAY_1')
            elif kind == 'currency':
                value = CURRENCIES.get(value.upper())
                if value is None:
                    raise Invalid('UNSUPPORTED_OR_AMBIGUOUS_CURRENCY')
            elif kind in ('money', 'rate'):
                if kind == 'money':
                    tokens = '|'.join(re.escape(x) for x in sorted(CURRENCIES, key=len, reverse=True))
                    match = re.fullmatch(r'(?:(%s)\s*)?(.+?)(?:\s*(%s))?' % (tokens, tokens), value, re.I)
                    if match:
                        prefix, number, suffix = match.groups()
                        code = CURRENCIES.get(str(raw.get('currency', source_currency)).strip().upper())
                        for token in (prefix, suffix):
                            if token and CURRENCIES[token.upper()] != code:
                                raise Invalid('AMOUNT_CURRENCY_MISMATCH')
                        value = number
                value = parse_number(value, 2 if kind == 'money' else 4)
                if kind == 'rate' and value > 1:
                    raise Invalid('RATE_OUTSIDE_0_1')
            elif name == 'status':
                value = STATUSES.get(value.casefold())
                if value is None:
                    raise Invalid('UNKNOWN_STATUS')
            elif len(value) > 1000:
                raise Invalid('TEXT_TOO_LONG')
            result[name] = value
        except Invalid as exc:
            errors.append({'field': name, 'code': str(exc)})
    if not errors and table == 'pms_reservations':
        if not result['booking_date'] <= result['check_in_date'] < result['check_out_date']:
            errors.append({'field': 'check_out_date', 'code': 'INVALID_DATE_ORDER'})
    if not errors and table == 'pms_stays':
        if result['actual_check_out'] and result['actual_check_out'] < result['actual_check_in']:
            errors.append({'field': 'actual_check_out', 'code': 'INVALID_DATE_ORDER'})
    return result, errors

RELATIONS = {
    'pms_rooms': [('hotel_id', 'pms_hotels', 'hotel_id')],
    'pms_reservations': [('hotel_id', 'pms_hotels', 'hotel_id'), ('guest_id', 'pms_guests', 'guest_id'), ('room_id', 'pms_rooms', 'room_id')],
    'pms_stays': [('reservation_id', 'pms_reservations', 'reservation_id'), ('guest_id', 'pms_guests', 'guest_id'), ('room_id', 'pms_rooms', 'room_id')],
    'cm_channels': [('reservation_id', 'pms_reservations', 'reservation_id')],
    'fin_budgets_costs': [('hotel_id', 'pms_hotels', 'hotel_id')],
}

def transform(snapshot, source_currencies=None, source_timezone='Europe/Warsaw'):
    """Each input row has exactly one terminal outcome. Conflicting keys reject ALL versions."""
    if set(snapshot) != set(SPECS):
        raise ValueError('All seven staging tables must be supplied')
    source_currencies = source_currencies or {}
    outputs, outcomes, indexes = {}, {}, {}
    for table, (key_fields, _) in SPECS.items():
        rows, groups = [], defaultdict(list)
        for position, raw in enumerate(snapshot[table], 1):
            data, errors = normalize(table, raw, source_currencies.get(table), source_timezone)
            row = {'position': position, 'raw': raw, 'data': data, 'errors': errors,
                   'outcome': 'rejected' if errors else 'accepted'}
            rows.append(row)
            if not errors:
                groups[tuple(data[k] for k in key_fields)].append(row)
        for group in groups.values():
            if any(r['data'] != group[0]['data'] for r in group[1:]):
                for r in group:
                    r['outcome'] = 'rejected'
                    r['errors'] = [{'field': ','.join(key_fields), 'code': 'CONFLICTING_BUSINESS_KEY'}]
                continue
            first = group[0]
            data = first['data']
            errors = []
            for col, parent, parent_key in RELATIONS.get(table, []):
                if data[col] not in indexes[parent]:
                    errors.append({'field': col, 'code': 'MISSING_PARENT'})
            if not errors and table == 'pms_reservations':
                if indexes['pms_rooms'][data['room_id']]['hotel_id'] != data['hotel_id']:
                    errors.append({'field': 'room_id', 'code': 'ROOM_HOTEL_MISMATCH'})
            if not errors and table == 'pms_stays':
                reservation = indexes['pms_reservations'][data['reservation_id']]
                for col in ('guest_id', 'room_id'):
                    if data[col] != reservation[col]:
                        errors.append({'field': col, 'code': 'STAY_RESERVATION_MISMATCH'})
            for i, r in enumerate(group):
                if errors:
                    r['outcome'], r['errors'] = 'rejected', errors
                elif i:
                    r['outcome'] = 'duplicate'
                    r['errors'] = [{'field': ','.join(key_fields), 'code': 'DUPLICATE'}]
        outputs[table] = [r['data'] for r in rows if r['outcome'] == 'accepted']
        outcomes[table] = rows
        # All referenced parents have a single-column key.
        indexes[table] = {r[key_fields[0]]: r for r in outputs[table]}
    return outputs, outcomes

def reconciliation(outcomes):
    """Account for each parseable amount by currency/outcome; invalid values stay explicit."""
    report = {}
    for table, rows in outcomes.items():
        counts = {k: sum(r['outcome'] == k for r in rows) for k in ('accepted', 'duplicate', 'rejected')}
        totals = defaultdict(lambda: {k: Decimal(0) for k in ('input', 'accepted', 'duplicate', 'rejected')})
        unparseable = defaultdict(int)
        for row in rows:
            for field, (kind, _) in SPECS[table][1].items():
                if kind != 'money':
                    continue
                data = row['data']
                if not isinstance(data.get(field), Decimal) or not data.get('currency'):
                    unparseable[field] += 1
                    continue
                entry = totals[data['currency'] + ':' + field]
                entry['input'] += data[field]
                entry[row['outcome']] += data[field]
        report[table] = {'input': len(rows), **counts, 'amounts': dict(totals), 'unparseable_amounts': dict(unparseable)}
        assert len(rows) == sum(counts.values())
        for entry in totals.values():
            assert entry['input'] == entry['accepted'] + entry['duplicate'] + entry['rejected']
    return report
