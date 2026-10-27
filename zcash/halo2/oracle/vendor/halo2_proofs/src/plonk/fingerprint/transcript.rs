use group::ff::FromUniformBytes;
use std::io::{self, Read};

use crate::arithmetic::CurveAffine;
use crate::transcript::{Blake2bRead, Challenge255, EncodedChallenge, Transcript, TranscriptRead};

/// One event observed by [`ChallengeRecorder`] while the verifier drives the transcript.
#[derive(Debug, Clone)]
pub enum TranscriptEvent<C: CurveAffine> {
    /// A common-input point absorbed into the transcript.
    CommonPoint(C),
    /// A common-input scalar absorbed into the transcript.
    CommonScalar(C::Scalar),
    /// A proof point read from the proof stream and absorbed into the transcript.
    ReadPoint(C),
    /// A proof scalar read from the proof stream and absorbed into the transcript.
    ReadScalar(C::Scalar),
    /// A verifier challenge squeezed from the transcript.
    Squeeze(C::Scalar),
}

/// A [`TranscriptRead`] wrapper that records every Fiat-Shamir challenge squeezed during
/// verification, so the verifier's challenges can be captured alongside its MSM (the fingerprint)
/// and fed to an independent model. It also records the ordered absorb/squeeze event stream used by
/// fixture generation to check the transcript schedule.
#[derive(Debug, Clone)]
pub struct ChallengeRecorder<R: Read, C: CurveAffine, E: EncodedChallenge<C>> {
    inner: Blake2bRead<R, C, E>,
    /// The challenge scalars squeezed so far, in squeeze order.
    pub challenges: Vec<C::Scalar>,
    /// Curve points read from the proof, in read order (the proof string's group elements).
    pub points: Vec<C>,
    /// Scalars read from the proof, in read order (the proof string's field elements).
    pub scalars: Vec<C::Scalar>,
    /// Curve points absorbed as common inputs (e.g. instance commitments), in order.
    pub common_points: Vec<C>,
    /// Ordered transcript events observed during verification.
    pub events: Vec<TranscriptEvent<C>>,
}

impl<R: Read, C: CurveAffine, E: EncodedChallenge<C>> ChallengeRecorder<R, C, E> {
    /// Initialize a recording transcript over the given input buffer.
    pub fn init(reader: R) -> Self {
        ChallengeRecorder {
            inner: Blake2bRead::init(reader),
            challenges: Vec::new(),
            points: Vec::new(),
            scalars: Vec::new(),
            common_points: Vec::new(),
            events: Vec::new(),
        }
    }
}

impl<R: Read, C: CurveAffine> Transcript<C, Challenge255<C>>
    for ChallengeRecorder<R, C, Challenge255<C>>
where
    C::Scalar: FromUniformBytes<64>,
{
    fn squeeze_challenge(&mut self) -> Challenge255<C> {
        let challenge = self.inner.squeeze_challenge();
        let scalar = challenge.get_scalar();
        self.challenges.push(scalar);
        self.events.push(TranscriptEvent::Squeeze(scalar));
        challenge
    }

    fn common_point(&mut self, point: C) -> io::Result<()> {
        self.common_points.push(point);
        self.events.push(TranscriptEvent::CommonPoint(point));
        self.inner.common_point(point)
    }

    fn common_scalar(&mut self, scalar: C::Scalar) -> io::Result<()> {
        self.events.push(TranscriptEvent::CommonScalar(scalar));
        self.inner.common_scalar(scalar)
    }
}

impl<R: Read, C: CurveAffine> TranscriptRead<C, Challenge255<C>>
    for ChallengeRecorder<R, C, Challenge255<C>>
where
    C::Scalar: FromUniformBytes<64>,
{
    fn read_point(&mut self) -> io::Result<C> {
        let point = self.inner.read_point()?;
        self.points.push(point);
        self.events.push(TranscriptEvent::ReadPoint(point));
        Ok(point)
    }

    fn read_scalar(&mut self) -> io::Result<C::Scalar> {
        let scalar = self.inner.read_scalar()?;
        self.scalars.push(scalar);
        self.events.push(TranscriptEvent::ReadScalar(scalar));
        Ok(scalar)
    }
}
