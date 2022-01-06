#include "integrator.h"


// inline void WaitEnter() { rootLogger.warn("Press Enter to continue..."); while (std::cin.get()!='\n'); }

template<class floatT, size_t HaloDepth, CompressionType comp=R18>
struct do_evolve_Q
{
    do_evolve_Q(gaugeAccessor<floatT, comp> gAcc,gaugeAccessor<floatT> pAccessor,floatT stepsize) : _stepsize(stepsize),
    _pAccessor(pAccessor), _gAcc(gAcc){}

    
    double _stepsize;
    gaugeAccessor<floatT> _pAccessor;
    gaugeAccessor<floatT, comp> _gAcc;

    __device__ __host__ GSU3<floatT> operator()(gSiteMu site){
        typedef GIndexer<All,HaloDepth> GInd;

        GSU3<double> temp;

        temp= su3_exp<double>(GCOMPLEX(double)(0.0,1.0)*_stepsize*_pAccessor.template getLink<double>(site)) 
        *_gAcc.template getLink<double>(site);

        temp.su3unitarize();

        return temp;
    }
};

template<class floatT, size_t HaloDepth>
struct do_evolve_P
{
    do_evolve_P(gaugeAccessor<floatT> ipdotAccessor,gaugeAccessor<floatT> pAccessor,floatT stepsize) : _stepsize(stepsize),
    _pAccessor(pAccessor), _ipdotAccessor(ipdotAccessor){}

    floatT _stepsize;
    gaugeAccessor<floatT> _pAccessor;
    gaugeAccessor<floatT> _ipdotAccessor;

    __device__ __host__ GSU3<floatT> operator()(gSiteMu site){
        typedef GIndexer<All,HaloDepth> GInd;

        GSU3<double> temp;

        temp = _pAccessor.template getLink<double>(site);
        temp -= GCOMPLEX(double)(0.0,1.0)*_stepsize *_ipdotAccessor.template getLink<double>(site);

        return temp;
    }
};

template<class floatT, size_t HaloDepth, CompressionType comp=R18>
struct get_gauge_Force
{
    gaugeAccessor<floatT, comp> _gAcc;
    floatT _beta;

    get_gauge_Force(gaugeAccessor<floatT, comp> gAcc, floatT beta) : _gAcc(gAcc), _beta(beta){}

    __device__ __host__ GSU3<floatT> operator()(gSiteMu siteM){
        typedef GIndexer<All,HaloDepth> GInd;
        gSite site(GInd::getSite(siteM.isite));

        GSU3<floatT> temp;
        // temp =- _beta/3.0*symanzikGaugeActionDeriv<floatT,HaloDepth>(_gAcc, site, siteM.mu);
        temp = gauge_force<floatT,HaloDepth,comp>(_gAcc, siteM, _beta);

        return temp;
    }
};


//only for testing 
template<class floatT, size_t HaloDepth>
struct get_mom_tr
{
    gaugeAccessor<floatT> _pAccessor;
    get_mom_tr(gaugeAccessor<floatT> pAccessor): _pAccessor(pAccessor){}

    __device__ __host__ floatT operator()(gSite site){
        typedef GIndexer<All,HaloDepth> GInd;

        floatT ret = 0.0;

        for (int mu = 0; mu < 4; mu++) {
            ret += abs(tr_c(_pAccessor.getLink(GInd::getSiteMu(site, mu))));
        }
        return ret;
    }
};

// this is called from outside, append switch cases if other integration schemes are added
template<class floatT, bool onDevice, Layout LatticeLayout, size_t HaloDepth, size_t HaloDepthSpin>
void integrator<floatT, onDevice, LatticeLayout, HaloDepth, HaloDepthSpin>::integrate(
    Spinorfield_container<floatT, onDevice, Even, HaloDepthSpin> &_phi_lf_container,
    Spinorfield_container<floatT, onDevice, Even, HaloDepthSpin> &_phi_sf_container){
    
    switch(_rhmc_param.integrator())
    {
        case 0:
            SWleapfrog(_phi_lf_container, _phi_sf_container);

             break;

        default:
            rootLogger.error("Only SW leapfroger implemented!");
    }
}


// Sexton-Weingarten integration scheme
template<class floatT, bool onDevice, Layout LatticeLayout, size_t HaloDepth, size_t HaloDepthSpin>
void integrator<floatT, onDevice, LatticeLayout, HaloDepth, HaloDepthSpin>::SWleapfrog(
    Spinorfield_container<floatT, onDevice, Even, HaloDepthSpin> &_phi_lf_container,
    Spinorfield_container<floatT, onDevice, Even, HaloDepthSpin> &_phi_sf_container){

    floatT ieps, iepsh, steph_sf, step_sf, sw_step, sw_steph;
    
    ieps = _rhmc_param.step_size();
    iepsh = 0.5 * ieps;

    step_sf = _rhmc_param.step_size()/_rhmc_param.no_step_sf();
    steph_sf = 0.5* step_sf;

    sw_step = step_sf/_rhmc_param.no_sw();
    sw_steph = 0.5 *sw_step;

    //==================================================//
    // Perform the first half step                      //
    //==================================================//

    updateP_fermforce( iepsh, _phi_lf_container, true );
    updateP_fermforce( steph_sf, _phi_sf_container, false );
    updateP_gaugeforce( sw_steph );


    rootLogger.info("Done first Leapfrog step");

    //==================================================//
    // Perform the next ( _no_md - 1 ) steps            //
    //==================================================//


    for (int md=1; md<_rhmc_param.no_md(); md++)                  // start loop over steps of lf
    {
        for (int step=1; step<=_rhmc_param.no_step_sf();step++)   // start loop over steps of sf
        {
            for (int sw=1; sw<=_rhmc_param.no_sw(); sw++)         // start loop over steps of gauge part
            {
                evolveQ( sw_step );
                updateP_gaugeforce( sw_step );
            }// end loop over steps of gauge part
            _smearing.SmearAll();
            // update P using only the sf part of the force
            rootLogger.info("strange force:");
            updateP_fermforce( step_sf, _phi_sf_container, false );
        }// end loop over steps of sf
        rootLogger.info("light force:");
        // update P using only the lf part of the force
        updateP_fermforce( ieps, _phi_lf_container, true );
    }  


    //==================================================//
    // Perform the last half step                       //
    //==================================================// 

    // bring P steph_sf away from the end of the trajectory for sf part of the force

    for (int step=1; step<_rhmc_param.no_step_sf(); step++)
    {
        for (int sw = 1; sw<=_rhmc_param.no_sw(); sw++)
        {
            evolveQ( sw_step );
            updateP_gaugeforce( sw_step );
        }
        _smearing.SmearAll();
        updateP_fermforce( step_sf, _phi_sf_container, false );
    }

    // bring P sw_steph away from the end of the trajectory for gauge part of the force

    for (int sw=1; sw<_rhmc_param.no_sw(); sw++)
    {
        evolveQ( sw_step );
        updateP_gaugeforce( sw_step );
    }
    

    // bring Q to the end of the trajectory

    evolveQ( sw_step );
    _smearing.SmearAll();
    // bring P to the end of the trajectory by updating with all the forces
    updateP_fermforce( steph_sf, _phi_sf_container, false );
    updateP_fermforce( iepsh, _phi_lf_container, true );
    updateP_gaugeforce( sw_steph );
}


//update P with the gauge force
template<class floatT, bool onDevice, Layout LatticeLayout, size_t HaloDepth, size_t HaloDepthSpin>
void integrator<floatT, onDevice, LatticeLayout, HaloDepth, HaloDepthSpin>::updateP_gaugeforce(floatT stepsize){

    ipdot.iterateOverBulkAllMu(get_gauge_Force<floatT,HaloDepth,R18>(gAcc, _rhmc_param.beta()));

    evolveP(stepsize);
}

//update P with the fermion force
template<class floatT, bool onDevice, Layout LatticeLayout, size_t HaloDepth, size_t HaloDepthSpin>
void integrator<floatT, onDevice, LatticeLayout, HaloDepth, HaloDepthSpin>::updateP_fermforce(floatT stepsize, 
    Spinorfield_container<floatT, onDevice, Even, HaloDepthSpin> &_phi, bool light/* std::vector<floatT> rat_coeff*/){
    
    for(int i = 0; i < _no_pf; i++) {
        ip_dot_f2_hisq.updateForce(_phi.phi_container.at(i),ipdot,light);
    }
    forceinfo();
    evolveP(stepsize);
}

template<class floatT, size_t HaloDepth>
struct trace
{

    trace(gaugeAccessor<floatT> ipdotAccessor) : _ipdotAccessor(ipdotAccessor){}

    gaugeAccessor<floatT> _ipdotAccessor;
    

    __device__ __host__ floatT operator()(gSite site){
        typedef GIndexer<All,HaloDepth> GInd;

        GSU3<floatT> temp;

        floatT ret =0.0;

        for(int mu=0; mu<4; mu++)
        {

        temp= _ipdotAccessor.getLink(GInd::getSiteMu(site, mu));

        ret += -2.0 * tr_d(temp,temp);

        }


        return ret;
    }
};

template<class floatT, bool onDevice, Layout LatticeLayout, size_t HaloDepth, size_t HaloDepthSpin>
void integrator<floatT, onDevice, LatticeLayout, HaloDepth, HaloDepthSpin>::forceinfo(){

    typedef GIndexer<All,HaloDepth> GInd;
    LatticeContainer<onDevice,floatT> force_tr(_p.getComm(), "forcetr");
    force_tr.adjustSize(GInd::getLatData().vol4);

    force_tr.template iterateOverBulk<All, HaloDepth>(trace<floatT, HaloDepth>(ipdotAccessor));

    floatT thing;
    force_tr.reduce(thing, GInd::getLatData().vol4);

    thing = thing /(4* GInd::getLatData().globvol4);



    rootLogger.info("Average force = " ,  thing);


}

// update the gauge field
template<class floatT, bool onDevice, Layout LatticeLayout, size_t HaloDepth, size_t HaloDepthSpin>
void integrator<floatT, onDevice, LatticeLayout, HaloDepth, HaloDepthSpin>::evolveQ(floatT stepsize){

    _gaugeField.iterateOverBulkAllMu(do_evolve_Q<floatT, HaloDepth, R18>(gAcc, pAccessor, stepsize));
    _gaugeField.updateAll();
}

//helper function, called in updateP_Xforce
template<class floatT, bool onDevice, Layout LatticeLayout, size_t HaloDepth, size_t HaloDepthSpin>
void integrator<floatT, onDevice, LatticeLayout, HaloDepth, HaloDepthSpin>::evolveP(floatT stepsize){

    _p.iterateOverBulkAllMu(do_evolve_P<floatT, HaloDepth>(ipdotAccessor, pAccessor, stepsize));
}

//test if momenta are traceless, only used in tests
template<class floatT, bool onDevice, Layout LatticeLayout, size_t HaloDepth, size_t HaloDepthSpin>
void integrator<floatT, onDevice, LatticeLayout, HaloDepth, HaloDepthSpin>::check_traceless(){

    typedef GIndexer<All,HaloDepth> GInd;
    LatticeContainer<onDevice,floatT> redBase(_p.getComm());
    const size_t elems = GInd::getLatData().vol4;

    redBase.adjustSize(elems);

    redBase.template iterateOverBulk<All, HaloDepth>(get_mom_tr<floatT, HaloDepth>(pAccessor));

    floatT momenta;

    redBase.reduce(momenta, elems);

    rootLogger.info("summed trace of momenta: " ,  momenta);
}


// this is called from outside, append switch cases if other integration schemes are added
template<class floatT, bool onDevice, size_t HaloDepth, CompressionType comp>
void pure_gauge_integrator<floatT, onDevice, HaloDepth, comp>::integrate(){

    PureGaugeleapfrog();
}


// Leapfrogger for pure gauge HMC
template<class floatT, bool onDevice, size_t HaloDepth, CompressionType comp>
void pure_gauge_integrator<floatT, onDevice, HaloDepth, comp>::PureGaugeleapfrog(){

    //==================================================//
    // Perform the first half step                      //
    //==================================================//

    updateP_gaugeforce( _rhmc_param.step_size()/2.0 );

    rootLogger.info("Done first Leapfrog step");

    //==================================================//
    // Perform the next ( _no_md - 1 ) steps            //
    //==================================================//

    for (int sw=1; sw<_rhmc_param.no_md(); sw++)
    {
        evolveQ( _rhmc_param.step_size() );
        updateP_gaugeforce( _rhmc_param.step_size() );
    }   

    //==================================================//
    // Perform the last half step                       //
    //==================================================// 

    evolveQ(_rhmc_param.step_size());
    updateP_gaugeforce( _rhmc_param.step_size()/2.0 );
}

//update P with the gauge force
template<class floatT, bool onDevice, size_t HaloDepth, CompressionType comp>
void pure_gauge_integrator<floatT, onDevice, HaloDepth, comp>::updateP_gaugeforce(floatT stepsize){

    ipdot.iterateOverBulkAllMu(get_gauge_Force<floatT,HaloDepth,comp>(gAcc, _rhmc_param.beta()));
    evolveP(stepsize);
    // check_traceless();
}


// update the gauge field
template<class floatT, bool onDevice, size_t HaloDepth, CompressionType comp>
void pure_gauge_integrator<floatT, onDevice, HaloDepth, comp>::evolveQ(floatT stepsize){

    _gaugeField.iterateOverBulkAllMu(do_evolve_Q<floatT, HaloDepth, comp>(gAcc, pAccessor, stepsize));
    _gaugeField.updateAll();
}

//helper function, called in updateP_Xforce
template<class floatT, bool onDevice, size_t HaloDepth, CompressionType comp>
void pure_gauge_integrator<floatT, onDevice, HaloDepth, comp>::evolveP(floatT stepsize){

    _p.iterateOverBulkAllMu(do_evolve_P<floatT, HaloDepth>(ipdotAccessor, pAccessor, stepsize));
}

//test if momenta are traceless, only used in tests
template<class floatT, bool onDevice, size_t HaloDepth, CompressionType comp>
void pure_gauge_integrator<floatT, onDevice, HaloDepth, comp>::check_traceless(){

    typedef GIndexer<All,HaloDepth> GInd;
    LatticeContainer<onDevice,floatT> redBase(_p.getComm());
    const size_t elems = GInd::getLatData().vol4;

    redBase.adjustSize(elems);

    redBase.template iterateOverBulk<All, HaloDepth>(get_mom_tr<floatT, HaloDepth>(pAccessor));

    floatT momenta;

    redBase.reduce(momenta, elems);

    rootLogger.info("summed trace of momenta: " ,  momenta);
}


// explicit instantiation
// template class integrator<float, All, 2>;
#define CLASS1_INIT(floatT, HALO, HALOSPIN)			\
template class integrator<floatT, true, All, HALO, HALOSPIN>;
#define CLASS2_INIT(floatT, HALO, comp) \
template class pure_gauge_integrator<floatT, true, HALO, comp>;

INIT_PHHS(CLASS1_INIT)
INIT_PHC(CLASS2_INIT)

