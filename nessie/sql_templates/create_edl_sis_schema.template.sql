/**
 * Copyright ©2021. The Regents of the University of California (Regents). All Rights Reserved.
 *
 * Permission to use, copy, modify, and distribute this software and its documentation
 * for educational, research, and not-for-profit purposes, without fee and without a
 * signed licensing agreement, is hereby granted, provided that the above copyright
 * notice, this paragraph and the following two paragraphs appear in all copies,
 * modifications, and distributions.
 *
 * Contact The Office of Technology Licensing, UC Berkeley, 2150 Shattuck Avenue,
 * Suite 510, Berkeley, CA 94720-1620, (510) 643-7201, otl@berkeley.edu,
 * http://ipira.berkeley.edu/industry-info for commercial licensing opportunities.
 *
 * IN NO EVENT SHALL REGENTS BE LIABLE TO ANY PARTY FOR DIRECT, INDIRECT, SPECIAL,
 * INCIDENTAL, OR CONSEQUENTIAL DAMAGES, INCLUDING LOST PROFITS, ARISING OUT OF
 * THE USE OF THIS SOFTWARE AND ITS DOCUMENTATION, EVEN IF REGENTS HAS BEEN ADVISED
 * OF THE POSSIBILITY OF SUCH DAMAGE.
 *
 * REGENTS SPECIFICALLY DISCLAIMS ANY WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE. THE
 * SOFTWARE AND ACCOMPANYING DOCUMENTATION, IF ANY, PROVIDED HEREUNDER IS PROVIDED
 * "AS IS". REGENTS HAS NO OBLIGATION TO PROVIDE MAINTENANCE, SUPPORT, UPDATES,
 * ENHANCEMENTS, OR MODIFICATIONS.
 */

--------------------------------------------------------------------
-- External schema
--------------------------------------------------------------------

DROP SCHEMA IF EXISTS {redshift_schema_edl_sis};
CREATE EXTERNAL SCHEMA {redshift_schema_edl_sis}
FROM data catalog
DATABASE 'cs_analytics'
IAM_ROLE '{redshift_iam_role},{edl_iam_role}';

--------------------------------------------------------------------
-- Internal schema
--------------------------------------------------------------------

DROP SCHEMA IF EXISTS {redshift_schema_edl_sis_internal} CASCADE;
CREATE SCHEMA {redshift_schema_edl_sis_internal};
GRANT USAGE ON SCHEMA {redshift_schema_edl_sis_internal} TO GROUP {redshift_dblink_group};
ALTER DEFAULT PRIVILEGES IN SCHEMA {redshift_schema_edl_sis_internal} GRANT SELECT ON TABLES TO GROUP {redshift_dblink_group};

--------------------------------------------------------------------
-- Internal tables
--------------------------------------------------------------------

CREATE TABLE {redshift_schema_edl_sis_internal}.student_degree_progress_index
SORTKEY (sid)
AS (
    SELECT
      student_id AS sid,
      reporting_dt AS report_date,
      CASE
        WHEN requirement_cd = '000000001' THEN 'entryLevelWriting'
        WHEN requirement_cd = '000000002' THEN 'americanHistory'
        WHEN requirement_cd = '000000003' THEN 'americanCultures'
        WHEN requirement_cd = '000000018' THEN 'americanInstitutions'
        ELSE NULL
      END AS requirement,
      requirement_desc,
      CASE
        WHEN requirement_status_cd = 'COMP' AND in_progress_grade_flg = 'Y' THEN 'In Progress'
        WHEN requirement_status_cd = 'COMP' AND in_progress_grade_flg = 'N' THEN 'Satisfied'
        ELSE 'Not Satisfied'
      END AS status,
      load_dt AS edl_load_date
    FROM {redshift_schema_edl_sis}.student_academic_progress_data
    WHERE requirement_group_cd = '000131'
    AND requirement_cd in ('000000001', '000000002', '000000003', '000000018')
);

CREATE TABLE {redshift_schema_edl_sis_internal}.student_degree_progress
(
    sid VARCHAR NOT NULL,
    feed VARCHAR(max) NOT NULL
)
DISTKEY (sid)
SORTKEY (sid);

CREATE TABLE {redshift_schema_edl_sis_internal}.student_majors
DISTKEY (sid)
SORTKEY (college, major)
AS (
    SELECT
      student_id AS sid,
      academic_plan_nm AS major,
      academic_program_nm AS college
    FROM {redshift_schema_edl_sis}.student_academic_plan_data
    WHERE academic_plan_type_cd in ('MAJ', 'SS', 'SP', 'HS', 'CRT')
);

CREATE TABLE {redshift_schema_edl_sis_internal}.student_minors
DISTKEY (sid)
SORTKEY (sid, minor)
AS (
    SELECT
      student_id AS sid,
      academic_plan_nm AS minor
    FROM {redshift_schema_edl_sis}.student_academic_plan_data
    WHERE academic_plan_type_cd = 'MIN'
);

CREATE TABLE {redshift_schema_edl_sis_internal}.student_profile_index
DISTKEY (units)
INTERLEAVED SORTKEY (sid, last_name, level, gpa, units, uid, first_name)
AS (
    SELECT
      reg.student_id AS sid,
      NULL AS uid,
      p.person_preferred_first_nm AS first_name,
      p.person_preferred_last_nm AS last_name,
      NULL AS level,
      reg.total_cumulative_gpa_nbr AS gpa,
      reg.total_units_completed_qty AS units,
      NULL AS transfer,
      reg.expected_graduation_term AS expected_grad_term,
      reg.terms_in_attendance,
      reg.load_dt AS edl_load_date
    FROM {redshift_schema_edl_sis}.student_registration_term_data reg
    JOIN {redshift_schema_edl_sis}.student_personal_data p
    ON reg.student_id = p.student_id
    WHERE reg.semester_year_term_cd = (
        SELECT MAX(semester_year_term_cd)
        FROM {redshift_schema_edl_sis}.student_registration_term_data max_reg
        WHERE max_reg.student_id = reg.student_id
    )
);
