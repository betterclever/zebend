//! Capture-only tooling for exporting the verifier's assembled MSM fingerprint.
//!
//! An `Ok` result from this module means capture and verifier assembly succeeded; it does not mean
//! the proof was accepted. Verification callers must continue to use [`super::SingleVerifier`].

use crate::arithmetic::CurveAffine;
use crate::poly::commitment::{Guard, Params, MSM};
use crate::transcript::{EncodedChallenge, TranscriptRead};

use super::{verify_proof, Error, VerificationStrategy, VerifyingKey};

mod transcript;

pub use transcript::{ChallengeRecorder, TranscriptEvent};

mod vesta_lean;

/// Internal strategy used by [`capture_proof_fingerprint`] to obtain the assembled verifier MSM
/// without evaluating it.
///
/// This deliberately remains private so callers cannot accidentally pass it to [`verify_proof`]
/// and mistake `Ok(msm)` for proof acceptance.
#[derive(Debug)]
struct FingerprintStrategy<'params, C: CurveAffine> {
    msm: MSM<'params, C>,
}

impl<'params, C: CurveAffine> FingerprintStrategy<'params, C> {
    fn new(params: &'params Params<C>) -> Self {
        FingerprintStrategy {
            msm: MSM::new(params),
        }
    }
}

impl<'params, C: CurveAffine> VerificationStrategy<'params, C> for FingerprintStrategy<'params, C> {
    type Output = MSM<'params, C>;

    fn process<E: EncodedChallenge<C>>(
        self,
        f: impl FnOnce(MSM<'params, C>) -> Result<Guard<'params, C, E>, Error>,
    ) -> Result<Self::Output, Error> {
        let guard = f(self.msm)?;
        Ok(guard.use_challenges())
    }
}

/// Captures the assembled verifier MSM — the "fingerprint" — without deciding whether it is the
/// group identity.
///
/// `Ok(msm)` means that proof parsing and verifier assembly succeeded; it **does not** mean the
/// proof is valid. A verification caller must use [`super::SingleVerifier`] instead. This API exists
/// only for tooling that inspects the exact MSM that `SingleVerifier` would evaluate.
pub fn capture_proof_fingerprint<
    'params,
    C: CurveAffine,
    E: EncodedChallenge<C>,
    T: TranscriptRead<C, E>,
>(
    params: &'params Params<C>,
    vk: &VerifyingKey<C>,
    instances: &[&[&[C::Scalar]]],
    transcript: &mut T,
) -> Result<MSM<'params, C>, Error> {
    verify_proof(
        params,
        vk,
        FingerprintStrategy::new(params),
        instances,
        transcript,
    )
}
