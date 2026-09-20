"""Reusable helper functions for the dissertation analysis notebook."""

from pathlib import Path

import geopandas as gpd
import numpy as np
import pandas as pd


DEFAULT_PRE_YEARS = ("2016", "2017", "2018", "2019", "2020")
DEFAULT_POST_YEARS = ("2021", "2022", "2023", "2024", "2025")


def get_price_columns(columns, years):
    """Return price_YYYY_MM columns whose year is in the provided list."""
    return [
        col for col in columns
        if col.startswith("price_") and col[6:10] in years
    ]


def assign_nearest_station(gdf, coords, names, distance_col="dist_to_station"):
    """Assign the nearest station name and distance to each geometry row."""
    house_xy = np.column_stack([gdf.geometry.x, gdf.geometry.y])
    diffs = house_xy[:, np.newaxis, :] - coords[np.newaxis, :, :]
    dists = np.sqrt((diffs ** 2).sum(axis=2))
    nearest_idx = dists.argmin(axis=1)
    gdf["nearest_station"] = names[nearest_idx]
    gdf[distance_col] = dists[np.arange(len(dists)), nearest_idx]
    return gdf


def create_control_group(
    operator_name,
    station_list,
    houses_gdf,
    stations_df,
    stations_treated_gdf,
):
    """Create a control group near operator stations but outside treated buffers."""
    stations_operator_df = stations_df[stations_df["Station name"].isin(station_list)]
    stations_operator_gdf = gpd.GeoDataFrame(
        stations_operator_df,
        geometry=gpd.points_from_xy(
            stations_operator_df["Eastings"],
            stations_operator_df["Northings"],
        ),
        crs="EPSG:27700",
    )
    stations_operator_gdf["buffer"] = stations_operator_gdf.geometry.buffer(1000)

    houses_near_operator = gpd.sjoin(
        houses_gdf,
        stations_operator_gdf.set_geometry("buffer"),
        how="inner",
        predicate="within",
    )
    houses_near_treated_all = gpd.sjoin(
        houses_gdf,
        stations_treated_gdf.set_geometry("buffer_3km"),
        how="inner",
        predicate="within",
    )

    operator_indices = set(houses_near_operator.index.unique())
    treated_indices = set(houses_near_treated_all.index.unique())
    operator_only_indices = operator_indices - treated_indices
    houses_control = houses_gdf.loc[list(operator_only_indices)].copy()

    op_coords = stations_operator_df[["Eastings", "Northings"]].astype(float).values
    op_names = stations_operator_df["Station name"].values
    houses_control = assign_nearest_station(
        houses_control,
        op_coords,
        op_names,
        distance_col="dist_to_operator",
    )
    houses_control = houses_control.reset_index(drop=True)

    print(f"Control group ({operator_name}): {len(houses_control)} houses")
    return houses_control


def apply_prepost_filter(
    df,
    pre_years=DEFAULT_PRE_YEARS,
    post_years=DEFAULT_POST_YEARS,
):
    """Filter to postcodes with at least one pre and one post transaction."""
    pre_cols = get_price_columns(df.columns, pre_years)
    post_cols = get_price_columns(df.columns, post_years)
    has_pre = df[pre_cols].notna().any(axis=1)
    has_post = df[post_cols].notna().any(axis=1)
    pc_has_pre = has_pre.groupby(df["postcode"]).transform("any")
    pc_has_post = has_post.groupby(df["postcode"]).transform("any")
    return df[pc_has_pre & pc_has_post]


def save_dta(df, filename, output_dir="output"):
    """Prepare and save a DataFrame as a Stata .dta file."""
    df_save = df.copy()
    keep_cols = [
        col for col in df_save.columns
        if df_save[col].dtype in ["int64", "float64", "object", "bool", "category"]
    ]
    df_save = pd.DataFrame(df_save[keep_cols])
    df_save.columns = df_save.columns.str.replace(" ", "_")
    for col in df_save.columns:
        if df_save[col].dtype == "object":
            df_save[col] = df_save[col].astype(str)

    output_path = Path(output_dir) / f"{filename}.dta"
    df_save.to_stata(output_path, write_index=False)
    return len(df_save)


def _build_estimation_sample(
    df,
    pre_years=DEFAULT_PRE_YEARS,
    post_years=DEFAULT_POST_YEARS,
    apply_fe_support=False,
):
    """Return long and house-level estimation samples matching Stata preprocessing."""
    years = tuple(pre_years) + tuple(post_years)
    price_cols = get_price_columns(df.columns, years)
    id_cols = [col for col in df.columns if col not in price_cols]

    long_df = df[id_cols + price_cols].melt(
        id_vars=id_cols,
        value_vars=price_cols,
        var_name="year_month",
        value_name="price",
    )
    year_month = long_df["year_month"].str.replace("price_", "", regex=False)
    long_df[["year", "month"]] = year_month.str.split("_", expand=True).astype(int)

    long_df = long_df.dropna(subset=["price"]).copy()
    long_df["additional_dwellings"] = np.nan

    for year in sorted(long_df["year"].unique()):
        ad_col = f"additional_dwellings_{year}"
        if ad_col in long_df.columns:
            long_df.loc[long_df["year"] == year, "additional_dwellings"] = long_df.loc[
                long_df["year"] == year, ad_col
            ]

    long_df = long_df.dropna(
        subset=[
            "additional_dwellings",
            "TOTAL_FLOOR_AREA",
            "NUMBER_HABITABLE_ROOMS",
            "EXTENSION_COUNT",
        ]
    ).copy()

    if apply_fe_support:
        pc_counts = long_df.groupby("postcode")["postcode"].transform("size")
        long_df = long_df[pc_counts >= 2].copy()
        long_df["station_year"] = (
            long_df["nearest_station"].astype(str) + "|" + long_df["year"].astype(str)
        )

        changed = True
        while changed:
            changed = False
            pc_counts = long_df.groupby("postcode")["postcode"].transform("size")
            station_year_counts = long_df.groupby("station_year")["station_year"].transform("size")
            keep = (pc_counts >= 2) & (station_year_counts >= 2)
            if keep.sum() < len(long_df):
                long_df = long_df[keep].copy()
                changed = True

    house_key_cols = [col for col in ["postcode", "PAON", "SAON"] if col in df.columns]
    if house_key_cols:
        house_df = df.merge(long_df[house_key_cols].drop_duplicates(), on=house_key_cols, how="inner")
    else:
        house_df = df.copy()

    return long_df, house_df


def estimation_baseline_stats(
    df,
    pre_years=DEFAULT_PRE_YEARS,
    post_years=DEFAULT_POST_YEARS,
    apply_fe_support=True,
    split_col=None,
):
    """Baseline descriptives on the Stata-style estimation sample."""
    long_df, house_df = _build_estimation_sample(
        df,
        pre_years=pre_years,
        post_years=post_years,
        apply_fe_support=apply_fe_support,
    )

    pre_year_ints = {int(year) for year in pre_years}
    post_year_ints = {int(year) for year in post_years}
    def _stats(long_frame, house_frame):
        pre_p = long_frame.loc[long_frame["year"].isin(pre_year_ints), "price"].to_numpy()
        post_p = long_frame.loc[long_frame["year"].isin(post_year_ints), "price"].to_numpy()
        tenure = house_frame["TENURE"].map(normalize_tenure)
        flat = house_frame["PROPERTY_TYPE"].astype(str).str.lower().eq("flat")
        return {
            "log_price_pre_mean": np.mean(np.log(pre_p)) if len(pre_p) else np.nan,
            "log_price_pre_sd": np.std(np.log(pre_p)) if len(pre_p) else np.nan,
            "log_price_post_mean": np.mean(np.log(post_p)) if len(post_p) else np.nan,
            "log_price_post_sd": np.std(np.log(post_p)) if len(post_p) else np.nan,
            "n_obs": len(long_frame),
            "n_postcodes": long_frame["postcode"].nunique() if "postcode" in long_frame.columns else np.nan,
            "flat_share": flat.mean(),
            "floor_area_mean": house_frame["TOTAL_FLOOR_AREA"].mean(),
            "rooms_mean": house_frame["NUMBER_HABITABLE_ROOMS"].mean(),
            "owner_share": (tenure == "owner").mean(),
            "private_share": (tenure == "private").mean(),
            "social_share": (tenure == "social").mean(),
            "old_stock_share": house_frame["CONSTRUCTION_AGE_BAND"].map(is_old_stock).mean(),
            "extension_mean": house_frame["EXTENSION_COUNT"].mean(),
        }

    stats = _stats(long_df, house_df)
    if split_col is not None and split_col in long_df.columns:
        by_group = {}
        for key, long_group in long_df.groupby(split_col):
            if split_col in house_df.columns:
                house_group = house_df[house_df[split_col] == key]
            else:
                house_group = house_df
            by_group[key] = _stats(long_group, house_group)
        stats["by_group"] = by_group
    return stats


def estimation_overall_stats(
    df,
    pre_years=DEFAULT_PRE_YEARS,
    post_years=DEFAULT_POST_YEARS,
    apply_fe_support=True,
    split_col=None,
):
    """Overall descriptives on the Stata-style estimation sample."""
    long_df, house_df = _build_estimation_sample(
        df,
        pre_years=pre_years,
        post_years=post_years,
        apply_fe_support=apply_fe_support,
    )

    def _stats(long_frame, house_frame):
        prices = long_frame["price"].to_numpy()
        tenure = house_frame["TENURE"].map(normalize_tenure)
        flat = house_frame["PROPERTY_TYPE"].astype(str).str.lower().eq("flat")
        return {
            "log_price_mean": np.mean(np.log(prices)) if len(prices) else np.nan,
            "log_price_sd": np.std(np.log(prices)) if len(prices) else np.nan,
            "n_obs": len(long_frame),
            "n_postcodes": long_frame["postcode"].nunique() if "postcode" in long_frame.columns else np.nan,
            "flat_share": flat.mean(),
            "floor_area_mean": house_frame["TOTAL_FLOOR_AREA"].mean(),
            "rooms_mean": house_frame["NUMBER_HABITABLE_ROOMS"].mean(),
            "owner_share": (tenure == "owner").mean(),
            "private_share": (tenure == "private").mean(),
            "social_share": (tenure == "social").mean(),
            "old_stock_share": house_frame["CONSTRUCTION_AGE_BAND"].map(is_old_stock).mean(),
            "extension_mean": house_frame["EXTENSION_COUNT"].mean(),
        }

    stats = _stats(long_df, house_df)
    if split_col is not None and split_col in long_df.columns:
        by_group = {}
        for key, long_group in long_df.groupby(split_col):
            if split_col in house_df.columns:
                house_group = house_df[house_df[split_col] == key]
            else:
                house_group = house_df
            by_group[key] = _stats(long_group, house_group)
        stats["by_group"] = by_group
    return stats


def estimation_support_counts(
    df,
    support_level,
    pre_years=DEFAULT_PRE_YEARS,
    post_years=DEFAULT_POST_YEARS,
):
    """Count estimation observations after support filters that mirror Stata."""
    long_df, _ = _build_estimation_sample(
        df,
        pre_years=pre_years,
        post_years=post_years,
        apply_fe_support=False,
    )

    post_cutoff = int(min(post_years))
    long_df = long_df.copy()
    long_df["post"] = (long_df["year"] >= post_cutoff).astype(int)
    long_df["station_year"] = (
        long_df["nearest_station"].astype(str) + "|" + long_df["year"].astype(str)
    )

    if support_level == "full":
        return len(long_df)

    if support_level == "postcode":
        long_df["support_group"] = long_df["postcode"].astype(str)
    elif support_level == "oa":
        group_has_pre = long_df.groupby("oa21cd")["post"].transform(lambda s: (s == 0).any())
        group_has_post = long_df.groupby("oa21cd")["post"].transform(lambda s: (s == 1).any())
        long_df = long_df[group_has_pre & group_has_post].copy()
        long_df["support_group"] = long_df["oa21cd"].astype(str)
    elif support_level == "station_ring":
        ring_bin = np.select(
            [
                long_df["dist_to_treated"] < 500,
                long_df["dist_to_treated"].between(500, 999.999),
                long_df["dist_to_treated"].between(1500, 1999.999),
                long_df["dist_to_treated"].between(2000, 2499.999),
                long_df["dist_to_treated"].between(2500, 3000),
            ],
            [1, 2, 3, 4, 5],
            default=np.nan,
        )
        long_df["ring_bin"] = ring_bin
        long_df = long_df[long_df["ring_bin"].notna()].copy()
        long_df["station_ring"] = (
            long_df["nearest_station"].astype(str) + "|" + long_df["ring_bin"].astype(int).astype(str)
        )
        group_has_pre = long_df.groupby("station_ring")["post"].transform(lambda s: (s == 0).any())
        group_has_post = long_df.groupby("station_ring")["post"].transform(lambda s: (s == 1).any())
        long_df = long_df[group_has_pre & group_has_post].copy()
        long_df["support_group"] = long_df["station_ring"]
    else:
        raise ValueError(f"Unsupported support_level: {support_level}")

    changed = True
    while changed:
        changed = False
        support_counts = long_df.groupby("support_group")["support_group"].transform("size")
        station_year_counts = long_df.groupby("station_year")["station_year"].transform("size")
        keep = (support_counts >= 2) & (station_year_counts >= 2)
        if keep.sum() < len(long_df):
            long_df = long_df[keep].copy()
            changed = True

    return len(long_df)


def normalize_tenure(x):
    """Map EPC tenure labels into broad categories."""
    if pd.isna(x):
        return np.nan
    s = str(x).strip().lower()
    if "owner" in s:
        return "owner"
    if "private" in s:
        return "private"
    if "social" in s:
        return "social"
    return np.nan


def is_old_stock(x):
    """Indicator for pre-1930 stock."""
    if pd.isna(x):
        return np.nan
    s = str(x).lower()
    return int(("before 1900" in s) or ("1900-1929" in s))


def format_row(label, vals, label_width, value_width):
    """Format a labeled row for printed summary tables."""
    return f"{label:<{label_width}}" + "".join(f"{v:>{value_width}}" for v in vals)


def format_blank_row(vals, label_width, value_width):
    """Format an unlabeled continuation row for printed summary tables."""
    return " " * label_width + "".join(f"{v:>{value_width}}" for v in vals)


def format_int_or_blank(x):
    """Format integers with commas, leaving missing values blank."""
    return f"{int(x):,}" if not np.isnan(float(x)) else ""


def make_gdf(df, crs="EPSG:27700"):
    """Convert a DataFrame with Eastings/Northings to a GeoDataFrame."""
    return gpd.GeoDataFrame(
        df,
        geometry=gpd.points_from_xy(df["Eastings"], df["Northings"]),
        crs=crs,
    )


def finalize_map(ax, center_x=532500, center_y=177500, width=85000, legend=False, title=None):
    """Apply standard London map bounds and basemap styling."""
    import contextily as ctx

    height = width * 9 / 16
    ax.set_xlim(center_x - width / 2, center_x + width / 2)
    ax.set_ylim(center_y - height / 2, center_y + height / 2)
    ax.set_aspect("equal")
    ctx.add_basemap(ax, crs="EPSG:27700", source=ctx.providers.OpenStreetMap.Mapnik, alpha=0.7)
    ax.set_axis_off()
    if legend:
        ax.legend(loc="upper right", fontsize=10)
    if title:
        ax.set_title(title, fontsize=14)
