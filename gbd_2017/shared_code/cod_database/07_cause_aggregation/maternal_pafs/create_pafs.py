import pandas as pd
import sys
import os
from get_draws.api import get_draws

this_dir = os.path.dirname(os.path.abspath(__file__))
repo_dir = os.path.abspath(os.path.join(this_dir, '../'))
sys.path.append(repo_dir)
import maternal_fns


def main(year):
    year = int(year)
    current_date = maternal_fns.get_time()
    current_date = current_date[0:10]
    out_dir = "FILEPATH"
    if not os.path.exists(out_dir):
        os.makedirs(out_dir)
    diag_out_dir = "FILEPATH"
    if not os.path.exists(diag_out_dir):
        os.makedirs(diag_out_dir)

    ############
    # Prep Work
    ############
    locations = maternal_fns.get_locations()
    columns = maternal_fns.filter_cols()
    rr_cols = []
    for i in range(0, 1000):
        rr_cols.append('rr_%d' % i)

    all_diag = pd.DataFrame()

    ############
    # Load data
    ############
    # load relative risks
    rr = pd.read_stata(
        'FILEPATH'
    )
    rr.drop('dummy', axis=1, inplace=True)
    rr = rr.reindex(range(0, 9))
    # propagate the relative risks down to all ages of interest
    rr['age_group_id'] = range(7, 16)
    rr.fillna(method='ffill', axis=0, inplace=True)
    rr.set_index('age_group_id', inplace=True)
    cols = rr.columns

    # rename all draw columns to be draw_0 to draw_999
    for idx, i in enumerate(cols):
        rr.rename(columns={'%s' % i: 'draw_%s' % idx}, inplace=True)

    print("pulling draws")
    all_pafs = pd.DataFrame()
    for geo in locations:
        hiv_prev = get_draws(
            gbd_id_type='modelable_entity_id', gbd_id=9313, source='epi',
            sex_id=2, location_id=geo, year_id=year,
            age_group_id=range(7, 16), gbd_round_id=5
        )

        hiv_prev = hiv_prev[columns]

        # we only want maternal age groups for hiv_prev
        hiv_prev.set_index('age_group_id', inplace=True)

        # replace all nulls with zeroes
        hiv_prev.fillna(0, inplace=True)

        # assert that HIV prevalence in pregnancy is between 0 and 1
        if (hiv_prev.values.any() < 0):
            raise ValueError(
                'HIV Prev values are below 0 for geo %s and year %s' % (geo, year)
            )
            continue
        elif (hiv_prev.values.any() > 1):
            raise ValueError(
                'HIV Prev values are above 1 for geo %s and year %s' % (geo, year)
            )
            continue

        ############
        # Math
        ############

        # multiply hiv prev for every loc/year/age by every rr draw using this
        pafs = (hiv_prev * (rr - 1)) / ((hiv_prev * (rr - 1)) + 1)

        # assert that all pafs are bounded between 0 and 1
        if (pafs.values.any() < 0):
            raise ValueError(
                'PAF values are below 0 for geo %s and year %s' % (geo, year))
            continue
        elif (pafs.values.any() > 1):
            raise ValueError(
                'PAF values are above 1 for geo %s and year %s' % (geo, year))
            continue

        pafs['location_id'] = geo
        pafs['year'] = year
        all_pafs = all_pafs.append(pafs)

        ############
        # Diagnostics
        ############
        # create paf_mean and find countries where paf is high to output seperately
        diagnostics = pafs.copy()
        diagnostics['paf_mean'] = diagnostics.mean(axis=1).to_frame()
        if diagnostics.paf_mean.any() >= .01:
            diagnostics['add'] = 0
        else:
            diagnostics['add'] = 1
        diagnostics['location_id'] = geo

        diagnostics.reset_index(inplace=True)
        all_diag = all_diag.append(diagnostics)

    ############
    # Save
    ############
    # output pafs as hdf
    print("saving")
    all_pafs.fillna(0, inplace=True)
    all_pafs.reset_index(inplace=True)
    all_pafs.convert_objects()
    all_pafs.to_hdf("FILEPATH")

    all_diag.to_csv("FILEPATH")


if __name__ == "__main__":
    year = sys.argv[1]
    main(year)
