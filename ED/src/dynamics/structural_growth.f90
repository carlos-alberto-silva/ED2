!==========================================================================================!
!==========================================================================================!
!    This is the module containing the routines that control growth of structural tissues, !
! and the change in population due to growth and mortality.                                !
!------------------------------------------------------------------------------------------!
module structural_growth
   contains

   !=======================================================================================!
   !=======================================================================================!
   !     This subroutine will control the structural growth of plants.                     !
   !                                                                                       !
   ! IMPORTANT: Do not change the order of operations below unless you know what you are   !
   !            doing.  Changing the order can affect the C/N budgets.                     !
   !---------------------------------------------------------------------------------------!
   subroutine dbstruct_dt(cgrid,veget_dyn_on)
      use ed_state_vars       , only : edtype                      & ! structure
                                     , polygontype                 & ! structure
                                     , sitetype                    & ! structure
                                     , patchtype                   ! ! structure
      use pft_coms            , only : seedling_mortality          & ! intent(in)
                                     , c2n_leaf                    & ! intent(in)
                                     , c2n_storage                 & ! intent(in)
                                     , c2n_recruit                 & ! intent(in)
                                     , c2n_stem                    & ! intent(in)
                                     , l2n_stem                    & ! intent(in)
                                     , negligible_nplant           & ! intent(in)
                                     , is_grass                    & ! intent(in)
                                     , agf_bs                      & ! intent(in)
                                     , is_liana                    & ! intent(in)
                                     , cbr_severe_stress           & ! intent(in)
                                     , h_edge                      & ! intent(in)
                                     , f_labile_leaf               & ! intent(in)
                                     , f_labile_stem               ! ! intent(in)
      use disturb_coms        , only : cl_fseeds_harvest           ! ! intent(in)
      use ed_max_dims         , only : n_pft                       & ! intent(in)
                                     , n_dbh                       ! ! intent(in)
      use ed_misc_coms        , only : igrass                      & ! intent(in)
                                     , iallom                      & ! intent(in)
                                     , ibigleaf                    & ! intent(in)
                                     , current_time                ! ! intent(in)
      use ed_therm_lib        , only : calc_veg_hcap               & ! function
                                     , update_veg_energy_cweh      ! ! function
      use physiology_coms     , only : ddmort_const                & ! intent(in)
                                     , iddmort_scheme              & ! intent(in)
                                     , cbr_scheme                  ! ! intent(in)
      use fuse_fiss_utils     , only : sort_cohorts                ! ! subroutine
      use stable_cohorts      , only : is_resolvable               ! ! subroutine
      use update_derived_utils, only : update_cohort_derived_props & ! subroutine
                                     , update_vital_rates          ! ! subroutine
      use allometry           , only : size2bl                     ! ! function
      use consts_coms         , only : yr_sec                      ! ! intent(in)
      implicit none
      !----- Arguments --------------------------------------------------------------------!
      type(edtype)     , target     :: cgrid
      logical          , intent(in) :: veget_dyn_on
      !----- Local variables --------------------------------------------------------------!
      type(polygontype), pointer    :: cpoly
      type(sitetype)   , pointer    :: csite
      type(patchtype)  , pointer    :: cpatch
      integer                       :: ipy
      integer                       :: isi
      integer                       :: ipa
      integer                       :: ico
      integer                       :: ipft
      integer                       :: prev_month
      integer                       :: prev_year
      integer                       :: prev_ndays
      integer                       :: imonth
      real                          :: tor_fact
      real                          :: bleaf_in
      real                          :: broot_in
      real                          :: bsapwooda_in
      real                          :: bsapwoodb_in
      real                          :: bsapw_in
      real                          :: bbark_in
      real                          :: balive_in
      real                          :: bdead_in
      real                          :: hite_in
      real                          :: dbh_in
      real                          :: nplant_in
      real                          :: bstorage_in
      real                          :: agb_in
      real                          :: phenstatus_in
      real                          :: lai_in
      real                          :: wai_in
      real                          :: cai_in
      real                          :: krdepth_in
      real                          :: ba_in
      real                          :: bag_in
      real                          :: bam_in
      real                          :: cb_act
      real                          :: cb_lightmax
      real                          :: cb_moistmax
      real                          :: cb_mlmax
      real                          :: cbr_light
      real                          :: cbr_moist
      real                          :: cbr_ml
      real                          :: f_bseeds
      real                          :: f_growth
      real                          :: f_bstorage
      real                          :: f_bleaf
      real                          :: f_broot
      real                          :: f_bsapa
      real                          :: f_bsapb
      real                          :: f_bbark
      real                          :: f_bdead
      real                          :: dbtot_i
      real                          :: bfast_mort_litter
      real                          :: bstruct_mort_litter
      real                          :: bstorage_mort_litter
      real                          :: bfast
      real                          :: bstruct
      real                          :: bstorage
      real                          :: maxh !< maximum patch height
      real                          :: mort_litter
      real                          :: bseeds_mort_litter
      real                          :: net_seed_N_uptake
      real                          :: net_stem_N_uptake
      real                          :: old_leaf_hcap
      real                          :: old_wood_hcap
      logical          , parameter  :: printout  = .false.
      character(len=17), parameter  :: fracfile  = 'struct_growth.txt'
      !----- Locally saved variables. -----------------------------------------------------!
      logical          , save       :: first_time = .true.
      !----- External function. -----------------------------------------------------------!
      integer          , external   :: num_days
      !------------------------------------------------------------------------------------!


      !----- First time, and the user wants to print the output.  Make a header. ----------!
      if (first_time) then

         !----- Make the header. ----------------------------------------------------------!
         if (printout) then
            open (unit=66,file=fracfile,status='replace',action='write')
            write (unit=66,fmt='(20(a,1x))')                                               &
              ,      '  YEAR',     '  MONTH',      '   DAY',      '   PFT',      '   ICO'  &
              ,'       BA_IN','      BAG_IN','      BAM_IN','      DBH_IN','   NPLANT_IN'  &
              ,'      BA_OUT','     BAG_OUT','     BAM_OUT','     DBH_OUT','  NPLANT_OUT'  &
              ,' TOTAL_BA_PY','TOTAL_BAG_PY','TOTAL_BAM_PY','TOTAL_BAR_PY','FIRST_CENSUS'
            close (unit=66,status='keep')
         end if
         !---------------------------------------------------------------------------------!

         first_time = .false.
      end if
      !------------------------------------------------------------------------------------!


      !----- Previous month (for crop yield update and carbon balance mortality). ---------!
      prev_month = 1 + modulo(current_time%month-2,12)
      select case (prev_month)
      case (12)
         prev_year = current_time%year -1
      case default
         prev_year = current_time%year
      end select
      prev_ndays = num_days(prev_month,prev_year)
      !----- Correction factor for sapwood turnover rate. ---------------------------------!
      tor_fact   = real(prev_ndays) / yr_sec
      !------------------------------------------------------------------------------------!


      polyloop: do ipy = 1,cgrid%npolygons
         cpoly => cgrid%polygon(ipy)


        !----- Initialization. ------------------------------------------------------------!
        cgrid%crop_yield(prev_month,ipy) = 0.0

         

         siteloop: do isi = 1,cpoly%nsites
            csite => cpoly%site(isi)
            !----- Initialization. --------------------------------------------------------!
            cpoly%basal_area(:,:,isi)       = 0.0
            cpoly%agb(:,:,isi)               = 0.0
            cpoly%crop_yield(prev_month,isi) = 0.0

            patchloop: do ipa=1,csite%npatches
               cpatch => csite%patch(ipa)

               !---------------------------------------------------------------------------!
               !    Here we must get the tallest tree cohort inside the patch. This will   !
               ! be then used to set the maximum height that lianas should aim at.         !
               ! Currently h_edge is set at 0.5m.  The arrested succession (only lianas    !
               ! inside the patch is a bit of a limit case: the maximum height will be set !
               ! to (0.5 + 0.5)m. It might still be reasonable.                            !
               !---------------------------------------------------------------------------!
               maxh = h_edge
               hcohortloop: do ico = 1,cpatch%ncohorts
                  if (.not. is_liana(cpatch%pft(ico)) .and. cpatch%hite(ico) > maxh) then
                     maxh = cpatch%hite(ico)
                  end if
               end do hcohortloop
               !---------------------------------------------------------------------------!

               !---------------------------------------------------------------------------!
               !    Add 0.5 to maxh has the effect of letting lianas grow 0.5 m above the  !
               ! tallest tree cohort. This number could be tweaked...                      !
               !---------------------------------------------------------------------------!
               maxh = maxh + h_edge
               !---------------------------------------------------------------------------!

               cohortloop: do ico = 1,cpatch%ncohorts

                  !----- Assigning an alias for PFT type. ---------------------------------!
                  ipft    = cpatch%pft(ico)
                  !------------------------------------------------------------------------!


                  !------------------------------------------------------------------------!
                  !      Remember inputs in order to calculate increments (and to revert   !
                  ! back to these values later on in case vegetation dynamics is off).     !
                  !------------------------------------------------------------------------!
                  balive_in     = cpatch%balive          (ico)
                  bdead_in      = cpatch%bdead           (ico)
                  bleaf_in      = cpatch%bleaf           (ico)
                  broot_in      = cpatch%broot           (ico)
                  bsapwooda_in  = cpatch%bsapwooda       (ico)
                  bsapwoodb_in  = cpatch%bsapwoodb       (ico)
                  bsapw_in      = bsapwooda_in + bsapwoodb_in
                  bbark_in      = cpatch%bbark           (ico)
                  hite_in       = cpatch%hite            (ico)
                  dbh_in        = cpatch%dbh             (ico)
                  nplant_in     = cpatch%nplant          (ico)
                  bstorage_in   = cpatch%bstorage        (ico)
                  agb_in        = cpatch%agb             (ico)
                  ba_in         = cpatch%basarea         (ico)
                  phenstatus_in = cpatch%phenology_status(ico)
                  lai_in        = cpatch%lai             (ico)
                  wai_in        = cpatch%wai             (ico)
                  cai_in        = cpatch%crown_area      (ico)
                  krdepth_in    = cpatch%krdepth         (ico)
                  bag_in      = sum(cpoly%basal_area_growth(ipft,:,isi))
                  bam_in      = sum(cpoly%basal_area_mort(ipft,:,isi))
                  !------------------------------------------------------------------------!

                  !------------------------------------------------------------------------!
                  !    Apply mortality, and do not allow nplant < negligible_nplant (such  !
                  ! a sparse cohort is about to be terminated, anyway).                    !
                  ! NB: monthly_dndt may be negative.                                      !
                  !------------------------------------------------------------------------!
                  cpatch%monthly_dndt  (ico) = max( cpatch%monthly_dndt   (ico)            &
                                                  , negligible_nplant     (ipft)           &
                                                  - cpatch%nplant         (ico) )
                  cpatch%monthly_dlnndt(ico) = max( cpatch%monthly_dlnndt (ico)            &
                                                  , log( negligible_nplant(ipft)           &
                                                       / cpatch%nplant    (ico) ) )
                  if (veget_dyn_on) then
                     cpatch%nplant(ico)      = cpatch%nplant(ico)                          &
                                             * exp(cpatch%monthly_dlnndt(ico))
                  end if
                  !------------------------------------------------------------------------!

                  !----- Split biomass components that are labile or structural. ----------!
                  bfast    = f_labile_leaf(ipft)                                           &
                           * ( cpatch%bleaf(ico) + cpatch%broot(ico) )                     &
                           + f_labile_stem(ipft)                                           &
                           * ( cpatch%bsapwooda(ico) + cpatch%bsapwoodb(ico)               &
                             + cpatch%bbark    (ico) + cpatch%bdead    (ico) )
                  bstruct  = ( 1.0 - f_labile_leaf(ipft) )                                 &
                           * ( cpatch%bleaf(ico) + cpatch%broot(ico) )                     &
                           + ( 1.0 - f_labile_stem(ipft) )                                 &
                           * ( cpatch%bsapwooda(ico) + cpatch%bsapwoodb(ico)               &
                             + cpatch%bbark    (ico) + cpatch%bdead    (ico) )
                  bstorage = cpatch%bstorage(ico)
                  !------------------------------------------------------------------------!


                  !----- Calculate litter owing to mortality. -----------------------------!
                  bfast_mort_litter    = - bfast    * cpatch%monthly_dndt(ico)
                  bstruct_mort_litter  = - bstruct  * cpatch%monthly_dndt(ico)
                  bstorage_mort_litter = - bstorage * cpatch%monthly_dndt(ico)
                  mort_litter          = bfast_mort_litter  + bstruct_mort_litter          &
                                       + bstorage_mort_litter 
                  !------------------------------------------------------------------------!



                  !----- Reset monthly_dndt. ----------------------------------------------!
                  cpatch%monthly_dndt  (ico) = 0.0
                  cpatch%monthly_dlnndt(ico) = 0.0
                  !------------------------------------------------------------------------!


                  !----- Determine how to distribute what is in bstorage. -----------------!
                  call plant_structural_allocation(cpatch%pft(ico),cpatch%hite(ico)        &
                                                  ,cpatch%dbh(ico),cgrid%lat(ipy)          &
                                                  ,cpatch%phenology_status(ico)            &
                                                  ,cpatch%elongf(ico)                      &
                                                  ,bdead_in, bstorage_in, maxh             &
                                                  ,f_bseeds,f_growth,f_bstorage)
                  !------------------------------------------------------------------------!



                  !------------------------------------------------------------------------!
                  !     Determine how to distribute what is in bstorage.  Here we must     !
                  ! check the allometry scheme.  The original method (subroutine           !
                  ! plant_structural_allocation) uses r_fract and st_fract to find the     !
                  ! partition between reproduction, storage, and heartwood growth.  This   !
                  ! method is always used by grasses and used by trees using the original  !
                  ! allometric schemes.  The revised method (subroutine grow_tissues)      !
                  ! grows structural tissues by applying turnover of sapwood that becomes  !
                  ! heartwood: st_fract is the minimum structural growth allocation, and   !
                  ! the remainder goes to reproduction.                                    !
                  !------------------------------------------------------------------------!
                  select case (iallom)
                  case (3)
                     !------ Use bdead/btotal ratio to decide total allocation to bdead. --!
                     call grow_tissues(cpatch,ipa,ico,tor_fact,f_bstorage,f_growth         &
                                      ,f_bseeds,f_bleaf,f_broot,f_bsapa,f_bsapb,f_bbark)
                     f_bdead    = 0.0
                     !---------------------------------------------------------------------!
                  case default
                     !------ Old scheme, use everything for bdead. ------------------------!
                     cpatch%bdead(ico) = cpatch%bdead(ico)                                 &
                                       + f_growth * cpatch%bstorage(ico)
                     f_bleaf    = 0.0
                     f_broot    = 0.0
                     f_bsapa    = 0.0
                     f_bsapb    = 0.0
                     f_bbark    = 0.0
                     f_bdead    = f_growth
                     !---------------------------------------------------------------------!
                  end select
                  !------------------------------------------------------------------------!



                  !------------------------------------------------------------------------!
                  !     Assign NPP allocation.                                             !
                  !------------------------------------------------------------------------!
                  select case (ibigleaf)
                  case (0)
                     !------ NPP allocation to wood and coarse roots in KgC /m2 -----------!
                     cpatch%today_nppwood   (ico) = agf_bs(ipft)                           &
                                                  * f_bdead * cpatch%bstorage(ico)         &
                                                  * cpatch%nplant(ico)
                     cpatch%today_nppcroot  (ico) = (1. - agf_bs(ipft))                    &
                                                  * f_bdead * cpatch%bstorage(ico)         &
                                                  * cpatch%nplant(ico)
                     cpatch%today_nppleaf   (ico) = cpatch%today_nppleaf(ico)              &
                                                  + f_bleaf * cpatch%bstorage(ico)         &
                                                  * cpatch%nplant(ico)
                     cpatch%today_nppfroot  (ico) = cpatch%today_nppfroot(ico)             &
                                                  + f_broot * cpatch%bstorage(ico)         &
                                                  * cpatch%nplant(ico)
                     cpatch%today_nppsapwood(ico) = cpatch%today_nppsapwood(ico)           &
                                                  + ( f_bsapa + f_bsapb )                  &
                                                  * cpatch%bstorage(ico)                   &
                                                  * cpatch%nplant(ico)
                     cpatch%today_nppbark   (ico) = cpatch%today_nppbark(ico)              &
                                                  + f_bbark * cpatch%bstorage(ico)         &
                                                  * cpatch%nplant(ico)
                  end select
                  !------------------------------------------------------------------------!



                  !------------------------------------------------------------------------!
                  !      Rebalance the plant nitrogen uptake considering the actual alloc- !
                  ! ation to structural growth.  This is necessary because c2n_stem does   !
                  ! not necessarily equal c2n_storage.                                     !
                  !------------------------------------------------------------------------!
                  net_stem_N_uptake = (cpatch%bdead(ico) - bdead_in) * cpatch%nplant(ico)  &
                                    * ( 1.0 / c2n_stem(cpatch%pft(ico)) - 1.0 / c2n_storage)
                  !------------------------------------------------------------------------!

                  !------------------------------------------------------------------------!
                  !      Calculate total seed production and seed litter.  The seed pool   !
                  ! gets a fraction f_bseeds of bstorage.  In case this is agriculture, we !
                  ! also set a fraction of seeds as crop yield.                            !
                  !------------------------------------------------------------------------!
                  select case (csite%dist_type(ipa))
                  case (8)
                     !---------------------------------------------------------------------!
                     !      Cropland patch.  Here we must account for harvesting of seeds. !
                     ! Leaves and non-structural carbon must be harvested at the end of    !
                     ! the cropland cycle.                                                 !
                     !---------------------------------------------------------------------!


                     !----- bseeds contains only non-harvested seeds. ---------------------!
                     cpatch%bseeds(ico) = (1.-cl_fseeds_harvest)                           &
                                        * f_bseeds * cpatch%bstorage(ico)
                     cpatch%byield(ico) = cl_fseeds_harvest                                &
                                        * f_bseeds * cpatch%bstorage(ico)
                     !---------------------------------------------------------------------!


                  case default
                     !---------------------------------------------------------------------!
                     !      Not a cropland patch. No harvesting should occur.              !
                     !---------------------------------------------------------------------!
                     cpatch%bseeds(ico) = f_bseeds * cpatch%bstorage(ico)
                     cpatch%byield(ico) = 0.
                     !---------------------------------------------------------------------!
                  end select
                  !------------------------------------------------------------------------!

                  !------------------------------------------------------------------------!
                  !      Net primary productivity used for seed production.  This must     !
                  ! include seeds that have been harvested.                                !
                  !------------------------------------------------------------------------!
                  cpatch%today_NPPseeds(ico) = cpatch%nplant(ico)                          &
                                             * f_bseeds * cpatch%bstorage(ico)
                  !------------------------------------------------------------------------!


                  !------------------------------------------------------------------------!
                  !      Send dead seeds to the litter pool (this time, only those that    !
                  ! were not harvested).                                                   !
                  !------------------------------------------------------------------------!
                  bseeds_mort_litter = cpatch%bseeds(ico) * cpatch%nplant(ico)             &
                                     * seedling_mortality(ipft)
                  !------------------------------------------------------------------------!


                  !------------------------------------------------------------------------!
                  !      Rebalance the plant nitrogen uptake considering the actual alloc- !
                  ! ation to seeds.  This is necessary because c2n_recruit does not have   !
                  ! to be equal to c2n_storage.  Here we must also account for harvested   !
                  !seeds.                                                                  !
                  !------------------------------------------------------------------------!
                  net_seed_N_uptake =  cpatch%nplant(ico)                                  &
                                    * f_bseeds * cpatch%bstorage(ico)                      &
                                    * (1.0 / c2n_recruit(ipft) - 1.0 / c2n_storage)
                  !------------------------------------------------------------------------!


                  !----- Decrement the storage pool due to allocation. --------------------!
                  cpatch%bstorage(ico) = cpatch%bstorage(ico) * f_bstorage
                  !------------------------------------------------------------------------!



                  !----- Finalize litter inputs. ------------------------------------------!
                  csite%fsc_in(ipa) = csite%fsc_in(ipa) + bfast_mort_litter                &
                                    + bstorage_mort_litter + bseeds_mort_litter
                  csite%fsn_in(ipa) = csite%fsn_in(ipa)                                    &
                                    + bfast_mort_litter    / c2n_leaf   (ipft)             &
                                    + bstorage_mort_litter / c2n_storage                   &
                                    + bseeds_mort_litter   / c2n_recruit(ipft)
                  csite%ssc_in(ipa) = csite%ssc_in(ipa) + bstruct_mort_litter
                  csite%ssl_in(ipa) = csite%ssl_in(ipa)                                    &
                                    + bstruct_mort_litter * l2n_stem / c2n_stem(ipft)
                  csite%total_plant_nitrogen_uptake(ipa) =                                 &
                         csite%total_plant_nitrogen_uptake(ipa) + net_seed_N_uptake        &
                       + net_stem_N_uptake
                  !------------------------------------------------------------------------!



                  !------ Update crop yield. ----------------------------------------------!
                  cpoly%crop_yield(prev_month,isi) = cpoly%crop_yield(prev_month,isi)      &
                                                   + cpatch%nplant(ico)                    &
                                                   * cpatch%byield(ico) * csite%area(ipa)
                  !------------------------------------------------------------------------!



                  !------------------------------------------------------------------------!
                  !     Calculate some derived cohort properties:                          !
                  ! - DBH                                                                  !
                  ! - Height                                                               !
                  ! - Recruit and census status                                            !
                  ! - Phenology status                                                     !
                  ! - Area indices                                                         !
                  ! - Basal area                                                           !
                  ! - AGB                                                                  !
                  ! - Rooting depth                                                        !
                  !------------------------------------------------------------------------!
                  call update_cohort_derived_props(cpatch,ico,cpoly%lsl(isi))
                  !------------------------------------------------------------------------!


                  !----- Update annual average carbon balances for mortality. -------------!
                  cpatch%cb          (prev_month,ico) = cpatch%cb          (13,ico)
                  cpatch%cb_lightmax (prev_month,ico) = cpatch%cb_lightmax (13,ico)
                  cpatch%cb_moistmax (prev_month,ico) = cpatch%cb_moistmax (13,ico)
                  cpatch%cb_mlmax    (prev_month,ico) = cpatch%cb_mlmax    (13,ico)
                  !------------------------------------------------------------------------!



                  !----- If monthly files are written, save the current carbon balance. ---!
                  if (associated(cpatch%mmean_cb)) then
                     cpatch%mmean_cb(ico)         = cpatch%cb(13,ico)
                  end if
                  !------------------------------------------------------------------------!



                  !------------------------------------------------------------------------!
                  !      Reset the current month integrator.  The initial value may depend !
                  ! on the storage.  By including this term we make sure that plants won't !
                  ! start dying as soon as they shed their leaves, but only when they are  !
                  ! in negative carbon balance and without storage.  This is done only     !
                  ! when iddmort_scheme is set to 1, otherwise the initial value is 0.     !
                  !------------------------------------------------------------------------!
                  select case (iddmort_scheme)
                  case (0)
                     !------ Storage is not accounted. ------------------------------------!
                     cpatch%cb          (13,ico) = 0.0
                     cpatch%cb_lightmax (13,ico) = 0.0
                     cpatch%cb_moistmax (13,ico) = 0.0
                     cpatch%cb_mlmax    (13,ico) = 0.0

                  case (1)
                   !------ Storage is accounted. ------------------------------------------!
                     cpatch%cb          (13,ico) = cpatch%bstorage(ico)
                     cpatch%cb_lightmax (13,ico) = cpatch%bstorage(ico)
                     cpatch%cb_moistmax (13,ico) = cpatch%bstorage(ico)
                     cpatch%cb_mlmax    (13,ico) = cpatch%bstorage(ico)
                  end select
                  !------------------------------------------------------------------------!

                  !------------------------------------------------------------------------!
                  !  Set up CB/CBmax as running sums and use that in the calculate cbr     !
                  !------------------------------------------------------------------------!

                  !----- Initialize with 0 ------------------------------------------------!
                  cb_act       = 0.0
                  cb_lightmax  = 0.0
                  cb_moistmax  = 0.0
                  cb_mlmax     = 0.0

                  !------------------------------------------------------------------------!
                  !      Compute the relative carbon balance.                              !
                  !------------------------------------------------------------------------!
                  if (is_grass(ipft).and. igrass==1) then  
                     !----- Grass loop, use past month's CB only. -------------------------!
                     cb_act      =  cpatch%cb          (prev_month,ico)
                     cb_lightmax =  cpatch%cb_lightmax (prev_month,ico)
                     cb_moistmax =  cpatch%cb_moistmax (prev_month,ico)
                     cb_mlmax    =  cpatch%cb_mlmax    (prev_month,ico)
                     !---------------------------------------------------------------------!
                  else  
                     !----- Tree loop, use annual average carbon balance. -----------------!
                     do imonth = 1,12
                        cb_act      = cb_act      + cpatch%cb          (imonth,ico)
                        cb_lightmax = cb_lightmax + cpatch%cb_lightmax (imonth,ico)
                        cb_moistmax = cb_moistmax + cpatch%cb_moistmax (imonth,ico)
                        cb_mlmax    = cb_mlmax    + cpatch%cb_mlmax    (imonth,ico)
                     end do
                     !---------------------------------------------------------------------!
                  end if
                  !------------------------------------------------------------------------!


                  !----- Light-related carbon balance. ------------------------------------!
                  if (cb_lightmax > 0.0) then
                     cbr_light = min(1.0, cb_act / cb_lightmax)
                  else
                     cbr_light = cbr_severe_stress(ipft)
                  end if
                  !------------------------------------------------------------------------!


                  !----- Soil moisture-related carbon balance. ----------------------------!
                  if (cb_moistmax > 0.0) then
                     cbr_moist = min(1.0, cb_act / cb_moistmax )
                  else
                     cbr_moist = cbr_severe_stress(ipft)
                  end if
                  !------------------------------------------------------------------------!


                  !----- Soil moisture+light related carbon balance. ----------------------!
                  if (cb_mlmax > 0.0) then
                     cbr_ml    = min(1.0, cb_act / cb_mlmax )
                  else
                     cbr_ml    = cbr_severe_stress(ipft)
                  end if
                  !------------------------------------------------------------------------!


                  !------------------------------------------------------------------------!
                  !  calculate CBR according to the specified CBR_SCHEME                   !
                  !------------------------------------------------------------------------!
                  select case (cbr_scheme)
                  case (0)
                     !----- CBR from absolute max CB --------------------------------------!
                     cpatch%cbr_bar(ico) = max(cbr_ml, cbr_severe_stress(ipft))
                     !---------------------------------------------------------------------!


                  case (1)
                     !---------------------------------------------------------------------!
                     !   CBR from combination of light & moist CBR                         !
                     !   Relative carbon balance: a combination of the two factors.        !
                     !---------------------------------------------------------------------!
                     if ( cbr_light <= cbr_severe_stress(ipft) .and.                       &
                          cbr_moist <= cbr_severe_stress(ipft)       ) then
                        cpatch%cbr_bar(ico) = cbr_severe_stress(ipft)
                     else
                        cpatch%cbr_bar(ico) = cbr_severe_stress(ipft)                      &
                                            + ( cbr_light - cbr_severe_stress(ipft) )      &
                                            * ( cbr_moist - cbr_severe_stress(ipft) )      &
                                            / (        ddmort_const  * cbr_moist           &
                                              + (1.0 - ddmort_const) * cbr_light           &
                                              - cbr_severe_stress(ipft) )
                     end if
                     !---------------------------------------------------------------------!

                  case (2)
                     !----- CBR from most limiting CBR ------------------------------------!
                     cpatch%cbr_bar(ico) = max( min(cbr_moist, cbr_light)                  &
                                              , cbr_severe_stress(ipft) )
                     !---------------------------------------------------------------------!
                  end select
                  !------------------------------------------------------------------------!



                  !----- Update interesting output quantities. ----------------------------!
                  call update_vital_rates(cpatch,ico,dbh_in,nplant_in,agb_in,ba_in         &
                                         ,csite%area(ipa),cpoly%basal_area(:,:,isi)        &
                                         ,cpoly%agb(:,:,isi)                               &
                                         ,cpoly%basal_area_growth(:,:,isi)                 &
                                         ,cpoly%agb_growth(:,:,isi)                        &
                                         ,cpoly%basal_area_mort(:,:,isi)                   &
                                         ,cpoly%agb_mort(:,:,isi))
                  !------------------------------------------------------------------------!




                  !------------------------------------------------------------------------!
                  !     In case vegetation dynamics is off, revert back to previous        !
                  ! values:                                                                !
                  !------------------------------------------------------------------------!
                  if (.not. veget_dyn_on) then
                     cpatch%balive          (ico) = balive_in
                     cpatch%bdead           (ico) = bdead_in
                     cpatch%bleaf           (ico) = bleaf_in
                     cpatch%broot           (ico) = broot_in
                     cpatch%bsapwooda       (ico) = bsapwooda_in
                     cpatch%bsapwoodb       (ico) = bsapwoodb_in
                     cpatch%bbark           (ico) = bbark_in
                     cpatch%hite            (ico) = hite_in
                     cpatch%dbh             (ico) = dbh_in
                     cpatch%nplant          (ico) = nplant_in
                     cpatch%bstorage        (ico) = bstorage_in
                     cpatch%agb             (ico) = agb_in
                     cpatch%basarea         (ico) = ba_in
                     cpatch%phenology_status(ico) = phenstatus_in
                     cpatch%lai             (ico) = lai_in
                     cpatch%wai             (ico) = wai_in
                     cpatch%crown_area      (ico) = cai_in
                     cpatch%krdepth         (ico) = krdepth_in
                  end if
                  !------------------------------------------------------------------------!



                  !------------------------------------------------------------------------!
                  ! MLO. We now update the heat capacity and the vegetation internal       !
                  !      energy.  Since no energy or water balance is done here, we simply !
                  !      update the energy in order to keep the same temperature and water !
                  !      as before.  Internal energy is an extensive variable, we just     !
                  !      account for the difference in the heat capacity to update it.     !
                  !------------------------------------------------------------------------!
                  old_leaf_hcap = cpatch%leaf_hcap(ico)
                  old_wood_hcap = cpatch%wood_hcap(ico)
                  call calc_veg_hcap(cpatch%bleaf(ico),cpatch%bdead(ico)                   &
                                    ,cpatch%bsapwooda(ico),cpatch%bbark(ico)               &
                                    ,cpatch%nplant(ico),cpatch%pft(ico)                    &
                                    ,cpatch%leaf_hcap(ico),cpatch%wood_hcap(ico) )
                  call update_veg_energy_cweh(csite,ipa,ico,old_leaf_hcap,old_wood_hcap)
                  call is_resolvable(csite,ipa,ico)
                  !------------------------------------------------------------------------!


                  !------------------------------------------------------------------------!
                  if (printout) then
                     open (unit=66,file=fracfile,status='old',position='append'            &
                          ,action='write')
                     write (unit=66,fmt='(5(i6,1x),14(f12.6,1x),1(11x,l1,1x))')            &
                        current_time%year,current_time%month,current_time%date,ipft,ico    &
                        ,ba_in,bag_in,bam_in,dbh_in,nplant_in                              &
                        ,cpatch%basarea(ico)                                               &
                        ,sum(cpoly%basal_area_growth(ipft,:,isi))                          &
                        ,sum(cpoly%basal_area_mort(ipft,:,isi))                            &
                        ,cpatch%dbh(ico),cpatch%nplant(ico)                                &
                        ,cgrid%total_basal_area(ipy)                                       &
                        ,cgrid%total_basal_area_growth(ipy)                                &
                        ,cgrid%total_basal_area_mort(ipy)                                  &
                        ,cgrid%total_basal_area_recruit(ipy)                               &
                        ,cpatch%first_census(ico)
                     close (unit=66,status='keep')
                  end if
                  !------------------------------------------------------------------------!

               end do cohortloop
               !---------------------------------------------------------------------------!

               !----- Age the patch if this is not agriculture. ---------------------------!
               if (csite%dist_type(ipa) /= 1) csite%age(ipa) = csite%age(ipa) + 1.0/12.0
               !---------------------------------------------------------------------------!

            end do patchloop
            !------------------------------------------------------------------------------!


            !------ Update polygon-level crop yield. --------------------------------------!
            cgrid%crop_yield(prev_month,ipy) = cgrid%crop_yield(prev_month,ipy)            &
                                             + cpoly%crop_yield(prev_month,isi)            &
                                             * cpoly%area(isi)
            !------------------------------------------------------------------------------!
         end do siteloop
         !---------------------------------------------------------------------------------!
      end do polyloop
      !------------------------------------------------------------------------------------!
      return
   end subroutine dbstruct_dt
   !=======================================================================================!
   !=======================================================================================!






   !=======================================================================================!
   !=======================================================================================!
   !     This subroutine will decide the partition of storage biomass into seeds and dead  !
   ! (structural) biomass.                                                                 !
   !---------------------------------------------------------------------------------------!
   subroutine plant_structural_allocation(ipft,hite,dbh,lat,phen_status,elongf,bdead       &
                                         ,bstorage,maxh,f_bseeds,f_growth,f_bstorage)
      use pft_coms      , only : phenology    & ! intent(in)
                               , repro_min_h  & ! intent(in)
                               , r_fract      & ! intent(in)
                               , st_fract     & ! intent(in)
                               , dbh_crit     & ! intent(in)
                               , hgt_max      & ! intent(in)
                               , is_grass     & ! intent(in)
                               , is_liana     ! ! intent(in)
      use ed_misc_coms  , only : current_time & ! intent(in)
                               , igrass       & ! intent(in)
                               , ibigleaf     & ! intent(in)
                               , iallom       ! ! intent(in)
      use consts_coms   , only : r_tol_trunc  ! ! intent(in)
      use allometry     , only : dbh2bd       & ! intent(in)
                               , h2dbh        ! ! intent(in)
      implicit none
      !----- Arguments --------------------------------------------------------------------!
      integer, intent(in)  :: ipft
      real   , intent(in)  :: hite
      real   , intent(in)  :: dbh
      real   , intent(in)  :: lat
      real   , intent(in)  :: bdead      !> Current dead biomass
      real   , intent(in)  :: bstorage   !> Current storage pool
      real   , intent(in)  :: maxh       !> Height of the tallest cohort in the patch
      integer, intent(in)  :: phen_status
      real   , intent(in)  :: elongf     !> Elongation factor
      real   , intent(out) :: f_bseeds   !> Fraction to use for reproduction
      real   , intent(out) :: f_growth   !> Fraction to use for growth
      real   , intent(out) :: f_bstorage !> Fraction to keep as storage
      !----- Local variables --------------------------------------------------------------!
      real                         :: bd_target  !> Target Bd to reach maxh height
      real                         :: delta_bd   !> Target Bd - actual Bd
      logical                      :: late_spring
      logical                      :: use_storage
      logical                      :: zero_growth
      logical                      :: zero_repro
      logical          , parameter :: printout  = .false.
      character(len=13), parameter :: fracfile  = 'storalloc.txt'
      !----- Locally saved variables. -----------------------------------------------------!
      logical          , save      :: first_time = .true.
      !------------------------------------------------------------------------------------!


      !----- First time, and the user wants to print the output.  Make a header. ----------!
      if (first_time) then

         !----- Make the header. ----------------------------------------------------------!
         if (printout) then
            open (unit=66,file=fracfile,status='replace',action='write')
            write (unit=66,fmt='(18(a,1x))')                                               &
              ,'  YEAR',' MONTH','   DAY','   PFT','PHENOL','PH_STT','SPRING',' GRASS'     &
              ,'      HEIGHT','   REPRO_HGT','         DBH','    DBH_CRIT','      ELONGF'  &
              ,'       BDEAD','    BSTORAGE','   F_STORAGE','     F_SEEDS','    F_GROWTH'
            close (unit=66,status='keep')
         end if
         !---------------------------------------------------------------------------------!

         first_time = .false.
      end if
      !------------------------------------------------------------------------------------!


      !----- Check whether this is late spring... -----------------------------------------!
      late_spring = (lat >= 0.0 .and. current_time%month ==  6) .or.                       &
                    (lat <  0.0 .and. current_time%month == 12)
      !------------------------------------------------------------------------------------!

      !----- Use storage. -----------------------------------------------------------------!
      select case (iallom)
      case (3)
         use_storage = (phenology(ipft) /= 2   .or.  late_spring) .and.                    &
                       phen_status >= 0  .and. elongf >= (1.-r_tol_trunc) .and.            &
                       bstorage > 0.0
      case default
         use_storage = (phenology(ipft) /= 2   .or.  late_spring) .and.                    &
                       phen_status == 0  .and. bstorage > 0.0
      end select
      !------------------------------------------------------------------------------------!

      select case (ibigleaf)
      case (0)
         !---------------------------------------------------------------------------------!
         !      Size and age structure.  Calculate fraction of bstorage going to bdead and !
         ! reproduction.  First we must make sure that the plant should do something here. !
         ! A plant should not allocate anything to reproduction or growth if it is not the !
         ! right time of year (for cold deciduous plants), or if the plants are actively   !
         ! dropping leaves or off allometry.                                               !
         !---------------------------------------------------------------------------------!
         if (use_storage) then
            !------------------------------------------------------------------------------!
            !      Decide allocation to seeds and heartwood based on size and life form.   !
            !------------------------------------------------------------------------------!
            if (is_liana(ipft)) then
               zero_growth = hite >= ( (1.0-r_tol_trunc) * maxh )
               zero_repro  = hite <  ( (1.0-r_tol_trunc) * repro_min_h(ipft) )

               !---------------------------------------------------------------------------!
               !    Lianas: we must check height relative to the rest of the local plant   !
               ! community.                                                                !
               !---------------------------------------------------------------------------!
               if (zero_growth) then
                  f_bseeds = merge(0.0, r_fract(ipft), zero_repro)
                  f_growth = 0.0
               else
                  bd_target = dbh2bd(h2dbh(maxh,ipft),ipft)
                  delta_bd = bd_target - bdead
                  !------------------------------------------------------------------------!
                  !    If bstorage is 0 or lianas have already reached their bd_target     !
                  ! don't grow otherwise invest what is needed (or everything in case it's !
                  ! not enough) to reach bd_target.                                        !
                  !    For seeds first check if the cohort has reached repro_min_h. In     !
                  ! case so, then check that it has enough left to invest r_fract in       !
                  ! reproduction.  In case so, invest r_fract in reproduction and the rest !
                  ! will stay in storage.  Otherwise, invest everything in reproduction.   !
                  ! Finally in case the liana hasn't reached repro_min_h, leave everything !
                  ! in storage.    !                                                       !
                  !------------------------------------------------------------------------!
                  f_growth  = merge(0.0                                                    &
                                   ,min(delta_bd / bstorage, 1.0)                          &
                                   ,bstorage * delta_bd <= 0.0)
                  f_bseeds  = merge( 0.0, min(r_fract(ipft),1.0-f_growth),zero_repro)
               end if
               !---------------------------------------------------------------------------!
            else if (is_grass(ipft) .and. igrass == 1) then
               !---------------------------------------------------------------------------!
               !     New grasses don't growth here (they do in dbalive_dt).  Decide        !
               ! whether they may reproduce or not.                                        !
               !---------------------------------------------------------------------------!
               zero_repro = hite <  ( (1.0-r_tol_trunc) * repro_min_h(ipft) )
               if (zero_repro) then
                  f_bseeds = 0.0
               else
                  f_bseeds = 1.0 - st_fract(ipft)
               end if
               f_growth = 0.0
               !---------------------------------------------------------------------------!
            else
               !---------------------------------------------------------------------------!
               !    Trees and old grasses.  Currently the only difference is that grasses  !
               ! stop growing once they reach maximum height (as they don't have an actual !
               ! DBH).                                                                     !
               !---------------------------------------------------------------------------!
               zero_repro  = hite <  ( (1.0-r_tol_trunc) * repro_min_h(ipft) )
               zero_growth = is_grass(ipft) .and.                                          &
                             hite >= ( (1.0-r_tol_trunc) * hgt_max(ipft)     )
               !---------------------------------------------------------------------------!


               !----- Decide allocation based on size. ------------------------------------!
               if (zero_growth) then
                  f_bseeds = 1.0 - st_fract(ipft)
                  f_growth = 0.0
               elseif (zero_repro) then
                  f_bseeds = 0.0
                  f_growth = 1.0 - st_fract(ipft)
               else
                  f_bseeds = r_fract(ipft)
                  f_growth = max(0.0,1.0 - st_fract(ipft) - r_fract(ipft))
               end if
               !---------------------------------------------------------------------------!
            end if
            !------------------------------------------------------------------------------!
         else  
            !----- Plant should not allocate carbon to seeds or grow new biomass. ---------!
            f_growth = 0.0
            f_bseeds = 0.0
            !------------------------------------------------------------------------------!
         end if
         !---------------------------------------------------------------------------------!
      case (1)
         !---------------------------------------------------------------------------------!
         !    Big-leaf solver.  As long as it is OK to grow, everything goes into          !
         ! 'reproduction'.  This will ultimately be used to increase NPLANT of the         !
         ! 'big leaf' cohort.                                                              !
         !---------------------------------------------------------------------------------!
         if (use_storage) then
            !------------------------------------------------------------------------------!
            ! A plant should only grow if it is the right time of year (for cold deciduous !
            ! plants), or if the plants are not actively dropping leaves or off allometry. !
            !------------------------------------------------------------------------------!
            f_bseeds = 1.0 - st_fract(ipft)
            f_growth = 0.0
         else
            f_growth = 0.0
            f_bseeds = 0.0
         end if
      end select
      !------------------------------------------------------------------------------------!


      !------------------------------------------------------------------------------------!
      !     Make sure allocation to growth and seeds is not negligible.                    !
      !------------------------------------------------------------------------------------!
      if (f_bseeds < r_tol_trunc) f_bseeds = 0.0
      if (f_growth < r_tol_trunc) f_growth = 0.0
      f_bstorage = 1.0 - f_growth - f_bseeds
      !------------------------------------------------------------------------------------!


      !------------------------------------------------------------------------------------!
      if (printout) then
         open (unit=66,file=fracfile,status='old',position='append',action='write')
         write (unit=66,fmt='(6(i6,1x),2(5x,l1,1x),10(f12.6,1x))')                         &
               current_time%year,current_time%month,current_time%date,ipft,phenology(ipft) &
              ,phen_status,late_spring,is_grass(ipft),hite,repro_min_h(ipft),dbh           &
              ,dbh_crit(ipft),elongf,bdead,bstorage,f_bstorage,f_bseeds,f_growth
         close (unit=66,status='keep')
      end if
      !------------------------------------------------------------------------------------!
      return
   end subroutine plant_structural_allocation
   !=======================================================================================!
   !=======================================================================================!





   !=======================================================================================!
   !=======================================================================================!
   !      This sub-routine increments structural biomass by applying sapwood turnover      !
   ! rates.  The allocation to seeds and growth is then adjusted depending on the          !
   ! availability of non-structural carbon and phenology status.                           !
   !---------------------------------------------------------------------------------------!
   subroutine grow_tissues(cpatch,ipa,ico,tor_fact,f_bstorage,f_growth,f_bseeds,f_bleaf    &
                          ,f_broot,f_bsapa,f_bsapb,f_bbark)
      use ed_state_vars, only : patchtype          ! ! structure
      use allometry    , only : size2bl            & ! function
                              , size2bw            & ! function
                              , dbh2h              & ! function
                              , bd2dbh             & ! function
                              , bw2dbh             ! ! function
      use pft_coms     , only : q                  & ! intent(in)
                              , qsw                & ! intent(in)
                              , qbark              & ! intent(in)
                              , sapw_turnover_rate & ! intent(in)
                              , bwood_crit         & ! intent(in)
                              , dbh_crit           & ! intent(in)
                              , agf_bs             & ! intent(in)
                              , is_grass           & ! intent(in)
                              , dbh_lut            ! ! intent(in)
      use therm_lib    , only : toler              & ! intent(in)
                              , maxfpo             ! ! intent(in)
      use ed_misc_coms , only : current_time       & ! intent(in)
                              , igrass             ! ! intent(in)
      use consts_coms  , only : tiny_num           ! ! intent(in)
      implicit none
      !------ Arguments. ------------------------------------------------------------------!
      type(patchtype), target          :: cpatch      ! Current patch 
      integer        , intent(in)      :: ipa         ! Index for current patch 
      integer        , intent(in)      :: ico         ! Index for current cohort 
      real(kind=4)   , intent(in)      :: tor_fact    ! Correction factor for monthly TO
      real(kind=4)   , intent(inout)   :: f_bstorage  ! Allocation to storage
      real(kind=4)   , intent(inout)   :: f_growth    ! Allocation to growth
      real(kind=4)   , intent(inout)   :: f_bseeds    ! Allocation to reproduction
      real(kind=4)   , intent(out)     :: f_bleaf     ! Allocation to leaf
      real(kind=4)   , intent(out)     :: f_broot     ! Allocation to fine roots
      real(kind=4)   , intent(out)     :: f_bsapa     ! Allocation to AG sapwood
      real(kind=4)   , intent(out)     :: f_bsapb     ! Allocation to BG sapwood
      real(kind=4)   , intent(out)     :: f_bbark     ! Allocation to bark
      !------ Local variables. ------------------------------------------------------------!
      integer                          :: ipft        ! Current PFT
      integer                          :: igrow       ! Growth case
      real(kind=4)                     :: dbh_t       ! Test for DBH
      real(kind=4)                     :: hite_t      ! Height (DBH_T)
      real(kind=4)                     :: bleaf_t     ! Leaf biomass (DBH_T)
      real(kind=4)                     :: broot_t     ! Fine root biomass (DBH_T)
      real(kind=4)                     :: bsapw_t     ! Sapwood biomass (DBH_T)
      real(kind=4)                     :: bsapa_t     ! AG sapwood biomass (DBH_T)
      real(kind=4)                     :: bsapb_t     ! BG sapwood root biomass (DBH_T)
      real(kind=4)                     :: bbark_t     ! Bark biomass (DBH_T)
      real(kind=4)                     :: bwood_t     ! Wood biomass (DBH_T)
      real(kind=4)                     :: balive_t    ! Live biomass if on-allometry
      real(kind=4)                     :: bleaf_b     ! Leaf biomass before growth
      real(kind=4)                     :: broot_b     ! Fine root biomass before growth
      real(kind=4)                     :: bsapa_b     ! AG sapwood biomass before growth
      real(kind=4)                     :: bsapb_b     ! BG sapwood biomass before growth
      real(kind=4)                     :: bwood_b     ! Wood biomass before growth
      real(kind=4)                     :: bbark_b     ! Bark biomass before growth
      real(kind=4)                     :: bdead_b     ! Heartwood biomass after turnover
      real(kind=4)                     :: bdead_a     ! Heartwood biomass before turnover
      real(kind=4)                     :: balive_a    ! Live biomass before turnover
      real(kind=4)                     :: balive_b    ! Live biomass before growth
      real(kind=4)                     :: bsapa_loss  ! AG Sapwood loss through turnover
      real(kind=4)                     :: bsapb_loss  ! BG Sapwood loss through turnover
      real(kind=4)                     :: bdead_gain  ! Heartwood gain through turnover
      real(kind=4)                     :: dt_bleaf    ! Leaf increment
      real(kind=4)                     :: dt_broot    ! Fine root increment
      real(kind=4)                     :: dt_bsapa    ! AG sapwood  increment
      real(kind=4)                     :: dt_bsapb    ! BG sapwood increment
      real(kind=4)                     :: dt_bbark    ! Bark increment
      real(kind=4)                     :: dt_balive   ! Live tissue increment
      !----- Local constants, for debugging. ----------------------------------------------!
      logical              , parameter :: printout  = .false.
      character(len=15)    , parameter :: growfile  = 'grow_tissue.txt'
      !----- Locally saved variables. -----------------------------------------------------!
      logical              , save      :: first_time = .true.
      !------------------------------------------------------------------------------------!




      !----- Handy aliases. ---------------------------------------------------------------!
      ipft = cpatch%pft(ico)
      !------------------------------------------------------------------------------------!


      !------------------------------------------------------------------------------------!
      !    New grasses don't have structural tissues, set all growth fraction to zero and  !
      ! return.                                                                            !
      !------------------------------------------------------------------------------------!
      if (igrass == 1 .and. is_grass(ipft)) then
         f_bleaf = 0.
         f_broot = 0.
         f_bsapa = 0.
         f_bsapb = 0.
         f_bbark = 0.
         return
      end if
      !------------------------------------------------------------------------------------!


      !----- First time, and the user wants to print the output.  Make a header. ----------!
      if (first_time) then

         !----- Make the header. ----------------------------------------------------------!
         if (printout) then
            open (unit=66,file=growfile,status='replace',action='write')
            write (unit=66,fmt='(23(a,1x))')                                               &
              ,      '  YEAR',      ' MONTH',      '   DAY',      '   IPA',      '   PFT'  &
              ,      ' IGROW',     '  DBH_A',     '  HGT_A', '   BALIVE_A', '   BALIVE_T'  &
              , '   BALIVE_Z', '   BSTORAGE', '    BDEAD_A', '    BDEAD_Z','  BDEAD_GAIN'  &
              ,    'F_GROWTH',    ' F_BLEAF',    ' F_BROOT',    ' F_BSAPA',    ' F_BSAPB'  &
              ,    ' F_BBARK',    'F_BSTORE',    'F_BSEEDS'
            close (unit=66,status='keep')
         end if
         !---------------------------------------------------------------------------------!

         first_time = .false.
      end if
      !------------------------------------------------------------------------------------!


      !----- Save biomass before turnover and growth. -------------------------------------!
      balive_a = cpatch%balive(ico)
      bdead_a  = cpatch%bdead (ico)
      !------------------------------------------------------------------------------------!


      !----- Find sapwood loss (and heartwood gain) through sapwood turnover. -------------!
      bsapa_loss            = cpatch%bsapwooda(ico) * sapw_turnover_rate(ipft) * tor_fact
      bsapb_loss            = cpatch%bsapwoodb(ico) * sapw_turnover_rate(ipft) * tor_fact
      bdead_gain            = bsapa_loss + bsapb_loss
      cpatch%bsapwooda(ico) = cpatch%bsapwooda(ico) - bsapa_loss
      cpatch%bsapwoodb(ico) = cpatch%bsapwoodb(ico) - bsapb_loss
      cpatch%bdead    (ico) = cpatch%bdead    (ico) + bdead_gain
      !------------------------------------------------------------------------------------!



      !----- Save the biomass before growth (but after sapwood turnover). -----------------!
      bleaf_b  = cpatch%bleaf    (ico)
      broot_b  = cpatch%broot    (ico)
      bsapa_b  = cpatch%bsapwooda(ico)
      bsapb_b  = cpatch%bsapwoodb(ico)
      bbark_b  = cpatch%bbark    (ico)
      bdead_b  = cpatch%bdead    (ico)
      bwood_b  = bsapa_b + bsapb_b + cpatch%bdead(ico)
      balive_b = bleaf_b + broot_b + bsapa_b + bsapb_b + bbark_b
      !------------------------------------------------------------------------------------!


      !------------------------------------------------------------------------------------!
      !      Find the goal for new biomass.  We assume all growth goes to wood, to obtain  !
      ! a first guess of the height, then adjust the ratio amongst living tissues.         !
      !------------------------------------------------------------------------------------!
      bwood_t  = bwood_b + f_growth * cpatch%bstorage(ico)
      dbh_t    = min(dbh_crit(ipft),bw2dbh(0.,0.,bwood_t,ipft))
      hite_t   = dbh2h (ipft,dbh_t)
      !------------------------------------------------------------------------------------!



      !----- Use the updated height to decide allocation. ---------------------------------!
      bleaf_t  = size2bl(dbh_t,hite_t,ipft)
      broot_t  = q(ipft) * bleaf_t
      bwood_t  = size2bw(dbh_t,hite_t,ipft)
      bsapw_t  = max( qsw(ipft) * hite_t * bleaf_t, bwood_t - bdead_b)
      bsapa_t  =        agf_bs(ipft)   * bsapw_t
      bsapb_t  = ( 1. - agf_bs(ipft) ) * bsapw_t
      bbark_t  = qbark(ipft) * hite_t * bleaf_t
      balive_t = bleaf_t + broot_t + bsapa_t + bsapb_t + bbark_t
      !------------------------------------------------------------------------------------!


      !----- Find the positive difference between current and goal. -----------------------!
      dt_bleaf  = max(0.,bleaf_t - bleaf_b)
      dt_broot  = max(0.,broot_t - broot_b)
      dt_bsapa  = max(0.,bsapa_t - bsapa_b)
      dt_bsapb  = max(0.,bsapb_t - bsapb_b)
      dt_bbark  = max(0.,bbark_t - bbark_b)
      dt_balive = dt_bleaf + dt_broot + dt_bsapa + dt_bsapb + dt_bbark
      !------------------------------------------------------------------------------------!


      !------------------------------------------------------------------------------------!
      !    Find the maximum increment that goes to increase in biomass.                    !
      !------------------------------------------------------------------------------------!
      if (f_growth == 0.) then
         !----- No growth is supposed to happen. ------------------------------------------!
         igrow      = -2
         f_bleaf    = 0.
         f_broot    = 0.
         f_bsapa    = 0.
         f_bsapb    = 0.
         f_bbark    = 0.
         !---------------------------------------------------------------------------------!
      elseif (dt_balive <= tiny_num) then
         !---------------------------------------------------------------------------------!
         !     In case current living biomass exceeds target biomass, allocate the         !
         ! excess carbon to reproduction, or storage in case the individual has not yet    !
         ! reached maturity.                                                               !
         !---------------------------------------------------------------------------------!
         igrow      = -1
         if (f_bseeds > 0.0) then
            f_bseeds   = 1. - f_bstorage
         else
            f_bstorage = 1. - f_bseeds
         end if
         f_growth   = 0.
         f_bleaf    = 0.
         f_broot    = 0.
         f_bsapa    = 0.
         f_bsapb    = 0.
         f_bbark    = 0.
         !---------------------------------------------------------------------------------!
      else
         !----- Plants can grow in size, find out by how much. ----------------------------!
         if ( dt_balive < f_growth * cpatch%bstorage(ico) ) then
            !------------------------------------------------------------------------------!
            !    Downregulate growth to enough to meet demand.  Allocate the excess to     !
            ! reproduction in case the individual has reached maturity, or storage other-  !
            ! wise.                                                                        !
            !------------------------------------------------------------------------------!
            igrow      = 1
            f_growth   = dt_balive / cpatch%bstorage(ico)
            if (f_bseeds > 0.0) then
               f_bseeds   = 1.0 - f_bstorage - f_growth
            else
               f_bstorage = 1.0 - f_bseeds   - f_growth
            end if
            !------------------------------------------------------------------------------!
         else
            !----- Amount needed for growth is more than maximum allowed. -----------------!
            igrow      = 0
            !------------------------------------------------------------------------------!
         end if
         !---------------------------------------------------------------------------------!


         !----- Increment balive. ---------------------------------------------------------!
         f_bleaf               = dt_bleaf * f_growth / dt_balive
         f_broot               = dt_broot * f_growth / dt_balive
         f_bsapa               = dt_bsapa * f_growth / dt_balive
         f_bsapb               = dt_bsapb * f_growth / dt_balive
         f_bbark               = dt_bbark * f_growth / dt_balive
         cpatch%bleaf    (ico) = cpatch%bleaf    (ico) + f_bleaf * cpatch%bstorage(ico)
         cpatch%broot    (ico) = cpatch%broot    (ico) + f_broot * cpatch%bstorage(ico)
         cpatch%bsapwooda(ico) = cpatch%bsapwooda(ico) + f_bsapa * cpatch%bstorage(ico)
         cpatch%bsapwoodb(ico) = cpatch%bsapwoodb(ico) + f_bsapb * cpatch%bstorage(ico)
         cpatch%bbark    (ico) = cpatch%bbark    (ico) + f_bbark * cpatch%bstorage(ico)
         cpatch%balive   (ico) = cpatch%bleaf    (ico) + cpatch%broot(ico)                 &
                               + cpatch%bsapwooda(ico) + cpatch%bsapwoodb(ico)             &
                               + cpatch%bbark    (ico)
         !---------------------------------------------------------------------------------!
      end if
      !------------------------------------------------------------------------------------!


      !------------------------------------------------------------------------------------!
      if (printout) then
         open (unit=66,file=growfile,status='old',position='append',action='write')
         write (unit=66,fmt='(6(i6,1x),2(f7.3,1x),6(f11.4,1x),1(es12.5,1x),8(f8.4,1x))')   &
               current_time%year,current_time%month,current_time%date,ipa,ipft,igrow       &
              ,cpatch%dbh(ico),cpatch%hite(ico),balive_a,balive_t,cpatch%balive(ico)       &
              ,cpatch%bstorage(ico),bdead_a,cpatch%bdead(ico),bdead_gain,f_growth,f_bleaf  &
              ,f_broot,f_bsapa,f_bsapb,f_bbark,f_bstorage,f_bseeds
         close (unit=66,status='keep')
      end if
      !------------------------------------------------------------------------------------!

      return
   end subroutine grow_tissues
   !=======================================================================================!
   !=======================================================================================!


end module structural_growth
!==========================================================================================!
!==========================================================================================!
